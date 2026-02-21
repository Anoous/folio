package client

import (
	"bytes"
	"context"
	"crypto/sha256"
	"fmt"
	"io"
	"net/http"
	"path"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type R2Client struct {
	s3Client   *s3.Client
	bucketName string
	publicURL  string
	httpClient *http.Client
}

func NewR2Client(endpoint, accessKey, secretKey, bucketName, publicURL string) (*R2Client, error) {
	s3Client := s3.New(s3.Options{
		BaseEndpoint: aws.String(endpoint),
		Region:       "auto",
		Credentials:  credentials.NewStaticCredentialsProvider(accessKey, secretKey, ""),
	})

	return &R2Client{
		s3Client:   s3Client,
		bucketName: bucketName,
		publicURL:  strings.TrimRight(publicURL, "/"),
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}, nil
}

func (c *R2Client) Upload(ctx context.Context, key string, body io.Reader, contentType string) (string, error) {
	buf, err := io.ReadAll(body)
	if err != nil {
		return "", fmt.Errorf("read body: %w", err)
	}

	_, err = c.s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(c.bucketName),
		Key:         aws.String(key),
		Body:        bytes.NewReader(buf),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return "", fmt.Errorf("upload to r2: %w", err)
	}

	return c.publicURL + "/" + key, nil
}

func (c *R2Client) DownloadAndUpload(ctx context.Context, sourceURL, keyPrefix string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", sourceURL, nil)
	if err != nil {
		return "", fmt.Errorf("create download request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("download image: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download failed: status %d", resp.StatusCode)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read image body: %w", err)
	}

	contentType := resp.Header.Get("Content-Type")
	ext := extensionFromContentType(contentType)

	hash := fmt.Sprintf("%x", sha256.Sum256(data))[:16]
	key := path.Join(keyPrefix, hash+ext)

	return c.Upload(ctx, key, bytes.NewReader(data), contentType)
}

func extensionFromContentType(ct string) string {
	switch {
	case strings.Contains(ct, "png"):
		return ".png"
	case strings.Contains(ct, "gif"):
		return ".gif"
	case strings.Contains(ct, "webp"):
		return ".webp"
	case strings.Contains(ct, "svg"):
		return ".svg"
	default:
		return ".jpg"
	}
}
