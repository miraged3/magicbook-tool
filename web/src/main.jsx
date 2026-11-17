import React, { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import * as Switch from '@radix-ui/react-switch'
import {
  AlertCircle, BatteryCharging, BriefcaseBusiness, Check, Home, Info,
  Laptop, Monitor, Moon, Plane, Power, Settings, SlidersHorizontal, Sun, Touchpad, Zap, PanelBottom,
} from 'lucide-react'
import './index.css'

const modes = [
  { name: '家庭模式', low: 40, high: 70, icon: Home },
  { name: '办公模式', low: 70, high: 90, icon: BriefcaseBusiness },
  { name: '旅行模式', low: 95, high: 100, icon: Plane },
  { name: '不限充', low: 0, high: 100, icon: Zap },
]
const pages = [
  { id: 'charging', title: '充电设置', icon: BatteryCharging },
  { id: 'other', title: '其他设置', icon: SlidersHorizontal },
  { id: 'preferences', title: '应用设置', icon: Settings },
  { id: 'about', title: '关于', icon: Info },
]
const initial = { percent: null, online: null, charging: false, low: null, high: null, lid: null, pad: null }

function percent(value) {
  return value == null ? '—' : `${value}%`
}

function ChargingSettings({ data, busy, send }) {
  const charge = data.percent == null ? null : Math.min(100, data.percent)
  let power = '状态未知'
  if (data.charging) power = charge === 100 ? '已充满' : '正在充电'
  else if (data.online === true) power = '已接通电源'
  else if (data.online === false) power = '电池供电'

  return (
    <>
      <section className="surface p-4" aria-label="电池状态">
        <div className="grid grid-cols-[1fr_auto_auto] items-end gap-5">
          <div>
            <div className="charge-value">{percent(charge)}</div>
            <div className="muted mt-1 text-xs">{power}</div>
          </div>
          <div>
            <div className="muted text-xs">充电上限</div>
            <div className="mt-1 text-sm font-semibold tabular-nums">{percent(data.high)}</div>
          </div>
          <div>
            <div className="muted text-xs">恢复充电阈值</div>
            <div className="mt-1 text-sm font-semibold tabular-nums">{percent(data.low)}</div>
          </div>
        </div>
        <div className="charge-track mt-3" aria-hidden="true">
          <div style={{ width: percent(charge ?? 0) }} />
        </div>
      </section>

      <section className="mt-5" aria-labelledby="mode-heading">
        <div className="mb-2.5 flex items-center justify-between">
          <h2 id="mode-heading" className="text-[13px] font-semibold">充电模式</h2>
          {data.low != null && !modes.some(mode => mode.low === data.low && mode.high === data.high) &&
            <span className="muted text-xs">当前为自定义阈值</span>}
        </div>
        <div className="grid grid-cols-2 gap-2">
          {modes.map(({ name, low, high, icon: Icon }) => (
            <button
              key={name}
              className="mode-button"
              disabled={busy || data.low == null}
              aria-pressed={data.low === low && data.high === high}
              onClick={() => send('mode', { low, high })}
            >
              <Icon size={17} strokeWidth={1.65} className="muted shrink-0" />
              <span className="grid flex-1 gap-0.5">
                <span className="text-[13px] font-medium">{name}</span>
                <span className="muted text-xs tabular-nums">{low}% – {high}%</span>
              </span>
              {data.low === low && data.high === high && <Check size={15} className="shrink-0" />}
            </button>
          ))}
        </div>
      </section>
    </>
  )
}

function DeviceRow({ icon: Icon, name, hint, children }) {
  return (
    <div className="device-row">
      <Icon size={18} strokeWidth={1.65} className="muted shrink-0" />
      <div className="flex-1">
        <div className="text-[13px] font-medium">{name}</div>
        {hint && <div className="muted mt-0.5 text-xs">{hint}</div>}
      </div>
      {children}
    </div>
  )
}

function DeviceSwitch({ name, value, busy, onChange }) {
  return (
    <Switch.Root
      aria-label={name}
      checked={value === true}
      disabled={busy || value == null}
      onCheckedChange={onChange}
      className="switch"
    >
      <Switch.Thumb className="switch-thumb" />
    </Switch.Root>
  )
}

function OtherSettings({ data, busy, send }) {
  return (
    <div className="surface">
      <DeviceRow icon={Laptop} name="开盖开机" hint={data.lid == null ? '状态不可读取' : undefined}>
        <DeviceSwitch name="开盖开机" value={data.lid} busy={busy} onChange={value => send('lid', { value })} />
      </DeviceRow>
      <DeviceRow icon={Touchpad} name="触控板" hint={data.pad == null ? '状态不可读取' : undefined}>
        <DeviceSwitch name="触控板" value={data.pad} busy={busy} onChange={value => send('pad', { value })} />
      </DeviceRow>
      <DeviceRow icon={Monitor} name="触摸屏">
        <div className="flex shrink-0 gap-2">
          <button
            className="outline-button"
            aria-label="启用触摸屏"
            disabled={busy || !data.available}
            onClick={() => send('touch', { value: true })}
          >
            启用
          </button>
          <button
            className="outline-button"
            aria-label="停用触摸屏"
            disabled={busy || !data.available}
            onClick={() => send('touch', { value: false })}
          >
            停用
          </button>
        </div>
      </DeviceRow>
    </div>
  )
}

function App() {
  const [page, setPage] = useState(pages[0])
  const [data, setData] = useState(initial)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState('')
  const [version, setVersion] = useState(null)
  const [preferences, setPreferences] = useState({ autoStart: null, closeToTray: null })
  const [theme, setTheme] = useState(() => {
    const saved = localStorage.getItem('honor-theme')
    if (saved === 'light' || saved === 'dark') return saved
    return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  })
  const inFlight = useRef(false)
  const dark = theme === 'dark'
  const ThemeIcon = dark ? Sun : Moon

  useEffect(() => {
    document.documentElement.dataset.theme = theme
    localStorage.setItem('honor-theme', theme)
    window.chrome?.webview?.postMessage({ action: 'appearance', dark })
  }, [theme, dark])

  useEffect(() => {
    const bridge = window.chrome?.webview
    if (!bridge) return
    const receive = ({ data: message }) => {
      if (message.type === 'state') setData(message)
      else if (message.type === 'about') setVersion(message.version)
      else if (message.type === 'preferences') setPreferences(message)
      else if (message.type === 'result') {
        inFlight.current = false
        setBusy(false)
        setNotice(message.error ?? '')
      }
    }
    bridge.addEventListener('message', receive)
    bridge.postMessage({ action: 'ready' })
    return () => bridge.removeEventListener('message', receive)
  }, [])

  useEffect(() => {
    if (!notice) return
    const timer = setTimeout(() => setNotice(''), 3500)
    return () => clearTimeout(timer)
  }, [notice])

  function send(action, payload) {
    const bridge = window.chrome?.webview
    if (!bridge || inFlight.current) return
    inFlight.current = true
    setBusy(true)
    setNotice('')
    bridge.postMessage({ action, ...payload })
  }

  return (
    <div className="shell">
      <aside className="sidebar">
        <nav aria-label="设置页面" className="grid gap-1">
          {pages.map(({ id, title, icon: Icon }, index) => (
            <button
              key={id}
              className="nav-button"
              aria-current={page.id === id ? 'page' : undefined}
              onClick={() => setPage(pages[index])}
            >
              <Icon size={17} strokeWidth={1.65} />
              {title}
            </button>
          ))}
        </nav>
        <button className="nav-button mt-auto" onClick={() => setTheme(dark ? 'light' : 'dark')}>
          <ThemeIcon size={17} strokeWidth={1.65} />
          {dark ? '浅色模式' : '深色模式'}
        </button>
      </aside>

      <main className="content" key={page.id}>
        <div className="mb-3 flex items-center justify-between">
          <h1 className="text-xl font-semibold tracking-tight">{page.title}</h1>
          {data.demo && <span className="muted text-xs">演示模式</span>}
        </div>
        {(page.id === 'charging' || page.id === 'other') && data.error && (
          <div role="alert" className="surface muted mb-3 flex items-start gap-2 p-2.5 text-xs">
            <AlertCircle size={15} className="shrink-0" />
            {data.error}
          </div>
        )}
        {page.id === 'charging' && <ChargingSettings data={data} busy={busy} send={send} />}
        {page.id === 'other' && <OtherSettings data={data} busy={busy} send={send} />}
        {page.id === 'preferences' && (
          <>
            {preferences.error && (
              <div role="alert" className="surface muted mb-3 flex items-center gap-2 p-2.5 text-xs">
                <AlertCircle size={15} className="shrink-0" />
                {preferences.error}
              </div>
            )}
            <div className="surface">
              <DeviceRow icon={Power} name="开机自动启动" hint="登录 Windows 后打开应用">
                <DeviceSwitch name="开机自动启动" value={preferences.autoStart} busy={busy}
                  onChange={value => send('autoStart', { value })} />
              </DeviceRow>
              <DeviceRow icon={PanelBottom} name="关闭窗口时隐藏到托盘" hint="通过托盘图标重新打开或退出">
                <DeviceSwitch name="关闭窗口时隐藏到托盘" value={preferences.closeToTray} busy={busy}
                  onChange={value => send('closeToTray', { value })} />
              </DeviceRow>
            </div>
          </>
        )}
        {page.id === 'about' && (
          <div className="surface flex items-center justify-between gap-3 px-3.5 py-3 text-[13px]">
            <span>荣耀硬件助手</span>
            <span className="muted text-xs tabular-nums">版本 {version ?? '—'}</span>
          </div>
        )}
      </main>
      {notice && <div role="status" className="surface fixed right-4 bottom-4 px-3 py-2 text-xs">{notice}</div>}
    </div>
  )
}

createRoot(document.getElementById('root')).render(<App />)
