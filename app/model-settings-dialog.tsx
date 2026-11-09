"use client";

import { LoaderCircle, X } from "lucide-react";
import { useEffect, useState } from "react";

type ModelSettings = {
  baseUrl: string;
  configured: boolean;
  hasApiKey: boolean;
  model: string;
};

async function responseJson<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

export function ModelSettingsDialog({
  onClose
}: {
  onClose: () => void;
}) {
  const [baseUrl, setBaseUrl] = useState("");
  const [apiKey, setApiKey] = useState("");
  const [model, setModel] = useState("");
  const [hasApiKey, setHasApiKey] = useState(false);
  const [loading, setLoading] = useState(true);
  const [testing, setTesting] = useState(false);
  const [saving, setSaving] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    void fetch("/api/model-settings", { cache: "no-store" })
      .then((response) => {
        if (!response.ok) {
          throw new Error("无法读取模型设置。");
        }
        return responseJson<ModelSettings>(response);
      })
      .then((settings) => {
        if (!active) {
          return;
        }
        setBaseUrl(settings.baseUrl);
        setModel(settings.model);
        setHasApiKey(settings.hasApiKey);
      })
      .catch((loadError) => {
        if (active) {
          setError(
            loadError instanceof Error
              ? loadError.message
              : "无法读取模型设置。"
          );
        }
      })
      .finally(() => {
        if (active) {
          setLoading(false);
        }
      });
    return () => {
      active = false;
    };
  }, []);

  function payload() {
    return { base_url: baseUrl, model, api_key: apiKey };
  }

  async function testConnection() {
    setTesting(true);
    setStatus(null);
    setError(null);
    try {
      const response = await fetch("/api/model-settings/test", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload())
      });
      const data = await responseJson<{ detail?: string; ok?: boolean }>(response);
      if (!response.ok || !data.ok) {
        throw new Error(data.detail ?? "连接失败。");
      }
      setStatus("连接成功");
    } catch (testError) {
      setError(testError instanceof Error ? testError.message : "连接失败。");
    } finally {
      setTesting(false);
    }
  }

  async function saveSettings() {
    setSaving(true);
    setStatus(null);
    setError(null);
    try {
      const response = await fetch("/api/model-settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload())
      });
      const data = await responseJson<ModelSettings & { detail?: string }>(
        response
      );
      if (!response.ok) {
        throw new Error(data.detail ?? "无法保存模型设置。");
      }
      setHasApiKey(data.hasApiKey);
      setApiKey("");
      onClose();
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : "无法保存模型设置。");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <div
        aria-labelledby="model-settings-title"
        aria-modal="true"
        className="dialog model-settings-dialog"
        role="dialog"
      >
        <div className="dialog-title-row">
          <div>
            <h2 id="model-settings-title">模型设置</h2>
            <p className="dialog-copy">
              使用你自己的 OpenAI-compatible 服务。资料片段会发送到这个服务。
            </p>
          </div>
          <button
            aria-label="关闭模型设置"
            className="icon-button"
            type="button"
            onClick={onClose}
          >
            <X aria-hidden="true" size={17} />
          </button>
        </div>

        {loading ? (
          <div className="settings-loading" role="status">
            <LoaderCircle className="spin" aria-hidden="true" size={17} />
            正在读取设置…
          </div>
        ) : (
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void saveSettings();
            }}
          >
            <label htmlFor="model-base-url">Base URL</label>
            <input
              autoFocus
              id="model-base-url"
              placeholder="https://api.example.com/v1"
              spellCheck={false}
              value={baseUrl}
              onChange={(event) => setBaseUrl(event.target.value)}
            />

            <label htmlFor="model-api-key">API Key</label>
            <input
              autoComplete="off"
              id="model-api-key"
              placeholder={hasApiKey ? "已保存在系统 Keychain，留空则不修改" : ""}
              type="password"
              value={apiKey}
              onChange={(event) => setApiKey(event.target.value)}
            />

            <label htmlFor="model-name">聊天模型</label>
            <input
              id="model-name"
              placeholder="gpt-4.1-mini"
              spellCheck={false}
              value={model}
              onChange={(event) => setModel(event.target.value)}
            />

            {status ? (
              <p className="settings-result is-success" role="status">
                {status}
              </p>
            ) : null}
            {error ? (
              <p className="settings-result is-error" role="alert">
                {error}
              </p>
            ) : null}

            <div className="dialog-actions settings-actions">
              <button
                className="secondary-text-button settings-test"
                disabled={testing || saving}
                type="button"
                onClick={() => void testConnection()}
              >
                {testing ? "正在测试…" : "测试连接"}
              </button>
              <button
                className="secondary-text-button"
                disabled={saving}
                type="button"
                onClick={onClose}
              >
                取消
              </button>
              <button
                className="primary-button"
                disabled={saving}
                type="submit"
              >
                {saving ? "正在保存…" : "保存设置"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
