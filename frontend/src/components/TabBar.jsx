import { useLocation, useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { effectiveRoutineIds, effectiveRoutines } from '../lib/history.js'
import { exCount, todayISO } from '../lib/format.js'
import { deriveSessionName } from '../lib/session-merge.js'
import { t } from '../lib/i18n.js'
import Icon from './Icon.jsx'

// Module scope, not TabBar's render body. Declared inside it, `Tab` was a new function on every
// render, so React saw a different component type each time and threw the button away and built a
// fresh one — on a bar that is fixed on screen, and once a second for the whole of a rest. The
// state it took with it is the DOM node itself: focus, the :active tint, any in-flight transition.
function Tab({ active, icon, label, onClick }) {
  return (
    <button className={active ? 'on' : ''} onClick={onClick}>
      <Icon name={icon} /><span>{label}</span>
    </button>
  )
}

// The iOS layout (docs/dev/IOS_NATIVE_UI.md): a floating glass capsule of three tabs, the
// exercise search as its own round button beside it, and above them the workout accessory —
// what a music app's mini player is to a song. It replaces the raised Start button that sat in
// the middle of the old bar: with no workout it offers today's session, during one it is the
// way back to it.
export default function TabBar({ onStart }) {
  const nav = useNavigate()
  const loc = useLocation()
  const S = useStore(s => s.S)
  const user = useStore(s => s.user)
  const isGuest = useStore(s => s.isGuest())
  if (!user && !isGuest) return null
  const cur = loc.pathname.split('/')[1] || 'home'
  const on = k => cur === k || (cur === 'history' && k === 'stats') || (cur === 'settings' && k === 'home') || (cur === 'muscles' && k === 'library') || (cur === 'structural-balance' && k === 'stats')

  const today = effectiveRoutines(S, todayISO()).filter(r => r.ex.length)
  const startWorkout = () => {
    if (!S.active) {
      // A weekday can hold several routines; start the combined session if any of them has
      // exercises, otherwise fall through to the picker.
      if (today.length) { onStart(effectiveRoutineIds(S, todayISO())); return }
    }
    nav('/workout')
  }

  // On the workout screen itself the accessory has nothing to offer: you are already there.
  const A = S.active
  const accessory = cur !== 'workout' && (
    <button className={'acc' + (A ? ' rec' : '')} onClick={startWorkout}>
      {A ? <span className="acc-dot" aria-hidden="true" /> : <Icon name="dumbbell" />}
      <span className="acc-t">
        <b>{A ? A.name : deriveSessionName(today.map(r => r.name)) || t('Start workout')}</b>
        {A
          ? <span> · {A.editingWorkoutId ? t('Edit workout') : t('Resume')}</span>
          : today.length ? <span> · {exCount(today.reduce((n, r) => n + r.ex.length, 0))}</span> : null}
      </span>
      <span className="acc-go"><Icon name="play" /></span>
    </button>
  )

  return (
    <div id="tabbar">
      {accessory}
      <div className="tb-row">
        <nav className="tb-pill">
          <Tab active={on('home')} icon="house" label={t('Home')} onClick={() => nav('/home')} />
          <Tab active={on('plan')} icon="calendar" label={t('Plan')} onClick={() => nav('/plan')} />
          <Tab active={on('stats')} icon="chart" label={t('Stats')} onClick={() => nav('/stats')} />
        </nav>
        <button className={'tb-search' + (on('library') ? ' on' : '')} aria-label={t('Exercises')} title={t('Exercises')} onClick={() => nav('/library')}>
          <Icon name="magnifier" />
        </button>
      </div>
    </div>
  )
}
