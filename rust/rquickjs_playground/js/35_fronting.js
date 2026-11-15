/**
 * 域名前置（IP 直连）的公开封装。
 *
 * 宿主内部用 `__http_*` 系列函数承载，插件侧只暴露 `fronting` 对象：
 * 参数与返回值都是普通对象，JSON 编解码在这里完成，插件不需要拼字符串。
 *
 * - `fronting.setHosts(table)`：下发 host → IP 列表
 * - `fronting.getHosts()`：读回表与每个 IP 的健康状态
 * - `fronting.clearHosts()`：清空表（等于关闭前置）
 * - `fronting.probe(payload, options)`：测延迟，返回 Promise
 * - `fronting.setEchHosts(table)`：登记走 ECH（加密 SNI）的域名；
 *   条目写 `{ ips: [...], pin: true }` 表示**只钉 IP、不做 ECH**（保留 SNI），
 *   给「DNS 被投毒但域名本身没被封」的域用（如 `*.picacomic.com`）
 * - `fronting.getEchHosts()` / `fronting.clearEchHosts()`：读回 / 清空 ECH 表
 *
 * 前置表为空时所有请求走原链路，对既有行为没有影响。
 */
(() => {
  const UNSUPPORTED = "fronting-unsupported";
  const INVALID_RESPONSE = "invalid-host-response";

  function parsePayload(raw, fallback) {
    try {
      const text = raw === undefined || raw === null ? "" : String(raw);
      const parsed = JSON.parse(text);
      if (!parsed || typeof parsed !== "object") return fallback;
      return parsed;
    } catch (_err) {
      return fallback;
    }
  }

  function errorMessage(err) {
    return String((err && err.message) || err);
  }

  const api = {
    setHosts(table) {
      const fn = globalThis.__http_set_front_hosts;
      if (typeof fn !== "function") return { ok: false, error: UNSUPPORTED };
      return parsePayload(fn(JSON.stringify(table || {})), {
        ok: false,
        error: INVALID_RESPONSE,
      });
    },

    getHosts() {
      const fn = globalThis.__http_get_front_hosts;
      if (typeof fn !== "function") {
        return { ok: false, hosts: {}, error: UNSUPPORTED };
      }
      return parsePayload(fn(), {
        ok: false,
        hosts: {},
        error: INVALID_RESPONSE,
      });
    },

    clearHosts() {
      const fn = globalThis.__http_clear_front_hosts;
      if (typeof fn !== "function") return { ok: false, error: UNSUPPORTED };
      return parsePayload(fn(), {
        ok: false,
        error: INVALID_RESPONSE,
      });
    },

    setEchHosts(table) {
      const fn = globalThis.__http_set_ech_hosts;
      if (typeof fn !== "function") return { ok: false, error: UNSUPPORTED };
      return parsePayload(fn(JSON.stringify(table || {})), {
        ok: false,
        error: INVALID_RESPONSE,
      });
    },

    getEchHosts() {
      const fn = globalThis.__http_get_ech_hosts;
      if (typeof fn !== "function") {
        return { ok: false, hosts: {}, error: UNSUPPORTED };
      }
      return parsePayload(fn(), {
        ok: false,
        hosts: {},
        error: INVALID_RESPONSE,
      });
    },

    clearEchHosts() {
      const fn = globalThis.__http_clear_ech_hosts;
      if (typeof fn !== "function") return { ok: false, error: UNSUPPORTED };
      return parsePayload(fn(), {
        ok: false,
        error: INVALID_RESPONSE,
      });
    },

    probe(payload, options) {
      const fn = globalThis.__http_probe_front_hosts;
      if (typeof fn !== "function") {
        return Promise.resolve({ ok: false, error: UNSUPPORTED });
      }

      const signal = options && options.signal;
      if (signal && signal.aborted) {
        return Promise.resolve({
          ok: false,
          canceled: true,
          error: "request-was-canceled",
        });
      }

      let promise;
      try {
        promise = fn(JSON.stringify(payload || {}));
      } catch (err) {
        return Promise.resolve({ ok: false, error: errorMessage(err) });
      }
      if (!promise || typeof promise.then !== "function") {
        return Promise.resolve(
          parsePayload(promise, { ok: false, error: INVALID_RESPONSE }),
        );
      }

      // 探测与普通请求共用取消通道：Promise 上带 `__hostRequestId`。
      const requestId = Number(promise.__hostRequestId);
      const cancel = globalThis.__http_request_cancel;
      const canCancel =
        Number.isFinite(requestId) &&
        requestId > 0 &&
        typeof cancel === "function";

      let onAbort = null;
      if (canCancel && signal && typeof signal.addEventListener === "function") {
        onAbort = () => {
          try {
            cancel(requestId);
          } catch (_err) {}
        };
        signal.addEventListener("abort", onAbort);
      }

      const cleanup = () => {
        if (
          onAbort &&
          signal &&
          typeof signal.removeEventListener === "function"
        ) {
          signal.removeEventListener("abort", onAbort);
        }
      };

      return promise.then(
        (raw) => {
          cleanup();
          return parsePayload(raw, { ok: false, error: INVALID_RESPONSE });
        },
        (err) => {
          cleanup();
          return { ok: false, error: errorMessage(err) };
        },
      );
    },
  };

  globalThis.__web.fronting = api;
})();
