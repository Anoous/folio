package pipeline

import (
	"errors"
	"fmt"
)

type Stage string

const (
	StageCrawlReader Stage = "crawl_reader"
	StageCrawlJina   Stage = "crawl_jina"
	StageAIAnalyze   Stage = "ai_analyze"
)

type Provider string

const (
	ProviderReader   Provider = "reader"
	ProviderJina     Provider = "jina"
	ProviderDeepSeek Provider = "deepseek"
)

type Code string

const (
	CodeInvalidRequest  Code = "invalid_request"
	CodeBlockedTarget   Code = "blocked_target"
	CodeTimeout         Code = "timeout"
	CodeNetwork         Code = "network"
	CodeRateLimited     Code = "rate_limited"
	CodeUpstream4xx     Code = "upstream_4xx"
	CodeUpstream5xx     Code = "upstream_5xx"
	CodeEmptyContent    Code = "empty_content"
	CodeInvalidResponse Code = "invalid_response"
	CodeInternal        Code = "internal"
)

type Error struct {
	Stage      Stage
	Provider   Provider
	Code       Code
	Retryable  bool
	StatusCode int
	Message    string
	Cause      error
}

func NewError(stage Stage, provider Provider, code Code, retryable bool, message string) *Error {
	return &Error{
		Stage:     stage,
		Provider:  provider,
		Code:      code,
		Retryable: retryable,
		Message:   message,
	}
}

func Wrap(stage Stage, provider Provider, code Code, retryable bool, statusCode int, message string, cause error) *Error {
	return &Error{
		Stage:      stage,
		Provider:   provider,
		Code:       code,
		Retryable:  retryable,
		StatusCode: statusCode,
		Message:    message,
		Cause:      cause,
	}
}

func (e *Error) Error() string {
	if e == nil {
		return "<nil>"
	}

	base := fmt.Sprintf("%s/%s/%s", e.Stage, e.Provider, e.Code)
	if e.Message != "" {
		base += ": " + e.Message
	}
	if e.Cause != nil {
		base += ": " + e.Cause.Error()
	}
	return base
}

func (e *Error) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.Cause
}

func As(err error) (*Error, bool) {
	var target *Error
	if errors.As(err, &target) {
		return target, true
	}
	return nil, false
}
