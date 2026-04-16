package middleware

import (
	"encoding/json"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"sync"
	"time"
)

type visitor struct {
	tokens   float64
	lastSeen time.Time
}

type RateLimiter struct {
	mu       sync.Mutex
	visitors map[string]*visitor
	rate     float64 // tokens per second
	burst    int
}

var trustedProxyPrefixes = []netip.Prefix{
	mustPrefix("127.0.0.0/8"),
	mustPrefix("10.0.0.0/8"),
	mustPrefix("172.16.0.0/12"),
	mustPrefix("192.168.0.0/16"),
	mustPrefix("169.254.0.0/16"),
	mustPrefix("100.64.0.0/10"),
	mustPrefix("::1/128"),
	mustPrefix("fc00::/7"),
	mustPrefix("fe80::/10"),
}

func NewRateLimiter(requestsPerMinute int, burst int) *RateLimiter {
	rl := &RateLimiter{
		visitors: make(map[string]*visitor),
		rate:     float64(requestsPerMinute) / 60.0,
		burst:    burst,
	}
	go rl.cleanup()
	return rl
}

func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		rl.mu.Lock()
		for ip, v := range rl.visitors {
			if time.Since(v.lastSeen) > 10*time.Minute {
				delete(rl.visitors, ip)
			}
		}
		rl.mu.Unlock()
	}
}

func (rl *RateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	v, exists := rl.visitors[ip]
	now := time.Now()
	if !exists {
		rl.visitors[ip] = &visitor{tokens: float64(rl.burst) - 1, lastSeen: now}
		return true
	}

	elapsed := now.Sub(v.lastSeen).Seconds()
	v.lastSeen = now
	v.tokens += elapsed * rl.rate
	if v.tokens > float64(rl.burst) {
		v.tokens = float64(rl.burst)
	}

	if v.tokens < 1 {
		return false
	}
	v.tokens--
	return true
}

func (rl *RateLimiter) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := clientIPFromRequest(r)

		if !rl.allow(ip) {
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("Retry-After", "60")
			w.WriteHeader(http.StatusTooManyRequests)
			json.NewEncoder(w).Encode(map[string]string{"error": "rate limit exceeded"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func clientIPFromRequest(r *http.Request) string {
	remote := clientIP(r.RemoteAddr)
	remoteAddr, ok := parseAddr(remote)
	if !ok || !isTrustedProxy(remoteAddr) {
		return remote
	}

	if forwarded := forwardedClientIP(r.Header.Get("X-Forwarded-For")); forwarded != "" {
		return forwarded
	}
	if realIP := forwardedClientIP(r.Header.Get("X-Real-IP")); realIP != "" {
		return realIP
	}

	return remote
}

func clientIP(remoteAddr string) string {
	ip, _, err := net.SplitHostPort(remoteAddr)
	if err != nil || ip == "" {
		return remoteAddr
	}
	return ip
}

func forwardedClientIP(header string) string {
	if header == "" {
		return ""
	}

	parts := strings.Split(header, ",")
	addrs := make([]netip.Addr, 0, len(parts))
	for _, part := range parts {
		if addr, ok := parseAddr(strings.TrimSpace(part)); ok {
			addrs = append(addrs, addr)
		}
	}

	for i := len(addrs) - 1; i >= 0; i-- {
		if !isTrustedProxy(addrs[i]) {
			return addrs[i].String()
		}
	}

	if len(addrs) > 0 {
		return addrs[0].String()
	}

	return ""
}

func parseAddr(raw string) (netip.Addr, bool) {
	addr, err := netip.ParseAddr(strings.TrimSpace(raw))
	if err != nil {
		return netip.Addr{}, false
	}
	return addr.Unmap(), true
}

func isTrustedProxy(addr netip.Addr) bool {
	for _, prefix := range trustedProxyPrefixes {
		if prefix.Contains(addr) {
			return true
		}
	}
	return false
}

func mustPrefix(raw string) netip.Prefix {
	return netip.MustParsePrefix(raw)
}
