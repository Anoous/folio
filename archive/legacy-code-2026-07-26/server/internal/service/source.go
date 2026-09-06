package service

import (
	"net/url"
	"strings"

	"folio-server/internal/domain"
)

func DetectSource(rawURL string) domain.SourceType {
	u, err := url.Parse(rawURL)
	if err != nil {
		return domain.SourceWeb
	}
	host := strings.ToLower(u.Host)

	switch {
	case strings.Contains(host, "mp.weixin.qq.com"):
		return domain.SourceWechat
	case strings.Contains(host, "twitter.com") || strings.Contains(host, "x.com"):
		return domain.SourceTwitter
	case strings.Contains(host, "weibo.com") || strings.Contains(host, "weibo.cn"):
		return domain.SourceWeibo
	case strings.Contains(host, "zhihu.com"):
		return domain.SourceZhihu
	case strings.Contains(host, "youtube.com") || strings.Contains(host, "youtu.be"):
		return domain.SourceYoutube
	case strings.Contains(host, "substack.com") || strings.Contains(host, "mailchi.mp"):
		return domain.SourceNewsletter
	default:
		return domain.SourceWeb
	}
}
