import type express from 'express';

export type RateLimitOptions = {
	windowMs: number;
	max: number;
	message?: string;
	keyGenerator?: (req: express.Request) => string;
};

type Counter = {
	count: number;
	resetAt: number;
};

// Minimal in-memory fixed-window rate limiter.
// Note: This is best-effort and per-instance. For multi-instance deployments,
// move this to a shared store (e.g., Redis).
export function createRateLimiter(options: RateLimitOptions): express.RequestHandler {
	const { windowMs, max, message, keyGenerator } = options;
	const counters = new Map<string, Counter>();

	return (req, res, next) => {
		const key = keyGenerator ? keyGenerator(req) : `${req.ip}`;
		const now = Date.now();
		const current = counters.get(key);

		if (!current || now >= current.resetAt) {
			counters.set(key, { count: 1, resetAt: now + windowMs });
			return next();
		}

		current.count += 1;
		if (current.count > max) {
			const retryAfterSec = Math.max(1, Math.ceil((current.resetAt - now) / 1000));
			res.setHeader('Retry-After', String(retryAfterSec));
			return res.status(429).json({ error: message ?? 'Too many requests' });
		}

		return next();
	};
}
