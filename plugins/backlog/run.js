#!/usr/bin/osascript -l JavaScript
// Backlog: a Markdown checklist in ~/.notchkeeper/backlog.md, one "## section" per repo.
// Notchkeeper runs this with an event on stdin; `notchkeeper todo …` runs it with arguments.
ObjC.import('Foundation')
ObjC.import('stdlib')

const home = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('HOME')) || $.NSHomeDirectory().js
const FILE = home + '/.notchkeeper/backlog.md'
const NOTCHKEEPER = home + '/.notchkeeper/bin/notchkeeper'
const ITEM = /^- \[( |x)\] (.*)$/
const REMIND = /\s*\((remind|reminded) (\d{4}-\d{2}-\d{2} \d{2}:\d{2})\)$/
const TAG = /^\s*(?:[-*]\s+)?(?:todo|follow[- ]?up|next(?: steps?)?)\s*:\s*(.+)$/i
const ASK = /^\s*(?:todo|remind me(?: to)?)\s*[:,]?\s+(.+)$/i

function run(argv) {
  if (argv.length) return cli(argv)
  const event = JSON.parse(readStdin())
  const settings = event.settings || {}
  const session = event.session || {}
  if (event.event === 'tick') return withLock(sendDueReminders)
  if (event.event === 'reply' && settings.collect) {
    const found = tagged(event.message || '')
    const model = modelFor(settings)
    if (model) found.push(...model.followUps(event.message || '', openIn(session.repo)))
    withLock(() => found.forEach(text => add(session.repo, text)))
  }
  if (event.event === 'prompt') {
    const task = askedFor(event.prompt || '', modelFor(settings))
    if (task) withLock(() => add(session.repo, task.text, task.at))
  }
}

// --- the file ---

function readLines() {
  const text = $.NSString.stringWithContentsOfFileEncodingError(FILE, $.NSUTF8StringEncoding, null)
  return text.isNil() ? ['# Backlog'] :text.js.replace(/\n+$/, '').split('\n')
}

function writeLines(lines) {
  $(lines.join('\n') + '\n').writeToFileAtomicallyEncodingError(FILE, true, $.NSUTF8StringEncoding, null)
  $.NSFileManager.defaultManager.setAttributesOfItemAtPathError($({ NSFilePosixPermissions: 0o600 }), FILE, null)
}

// Events can arrive together; a lock folder keeps two runs from writing over each other.
function withLock(body) {
  const lock = FILE + '.lock'
  const fm = $.NSFileManager.defaultManager
  for (let i = 0; i < 40; i++) {
    if (fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(lock, false, $(), null)) {
      try { return body() } finally { fm.removeItemAtPathError(lock, null) }
    }
    const made = fm.attributesOfItemAtPathError(lock, null)
    if (!made.isNil() && new Date() - new Date(made.fileModificationDate.timeIntervalSince1970 * 1000) > 15000) {
      fm.removeItemAtPathError(lock, null)
    }
    delay(0.1)
  }
}

function parse(lines) {
  let section = ''
  const items = []
  lines.forEach((line, index) => {
    const header = line.match(/^## (.+)$/)
    if (header) section = header[1]
    const item = line.match(ITEM)
    if (!item) return
    const remind = item[2].match(REMIND)
    items.push({ index, section, done: item[1] === 'x', text: item[2].replace(REMIND, ''),
                 at: remind ? remind[2] : null, sent: remind ? remind[1] === 'reminded' : false })
  })
  return items
}

const clean = text => text.replace(/\*\*|`/g, '').replace(/\s+/g, ' ').trim().slice(0, 200)
const same = (a, b) => a.toLowerCase().replace(/[^a-z0-9]/g, '') === b.toLowerCase().replace(/[^a-z0-9]/g, '')

// Adds under its section (made if missing), unless that section already has it.
function add(section, text, at) {
  section = clean(section || '').replace(/^#+\s*/, '') || 'Inbox'
  text = clean(text)
  if (!text) return false
  const lines = readLines()
  const items = parse(lines)
  if (items.some(item => item.section === section && same(item.text, text))) return false
  const line = '- [ ] ' + text + (at ? ' (remind ' + at + ')' : '')
  const last = items.filter(item => item.section === section).pop()
  if (last) lines.splice(last.index + 1, 0, line)
  else {
    const header = lines.indexOf('## ' + section)
    if (header >= 0) lines.splice(header + 1, 0, line)
    else lines.push('', '## ' + section, line)
  }
  writeLines(lines)
  return true
}

const openIn = section => parse(readLines()).filter(item => !item.done && item.section === (section || 'Inbox')).map(item => item.text)

// --- finding tasks ---

function tagged(message) {
  return message.replace(/\*\*/g, '').split('\n').map(line => (line.match(TAG) || [])[1]).filter(Boolean)
}

// "remind me to call Sam at 3pm" or "todo: bump the version": the start of a prompt, or anywhere with a model.
function askedFor(prompt, model) {
  if (model && /\b(remind me|todo|don'?t forget)\b/i.test(prompt)) {
    const task = model.reminder(prompt)
    if (task) return task
  }
  const asked = prompt.split('\n')[0].match(ASK)
  return asked ? splitWhen(asked[1]) : null
}

// "call Sam at 3pm" → { text: "call Sam", at: "2026-11-15 15:00" }
function splitWhen(text) {
  const tail = text.match(/^(.*?)\s+((?:in \d+\s*\w+)|(?:(?:today|tomorrow)(?: (?:at )?[\d:]+\s*(?:am|pm)?)?)|(?:at [\d:]+\s*(?:am|pm)?))[.!]?$/i)
  const at = tail && when(tail[2])
  return at ? { text: tail[1], at } : { text, at: null }
}

function when(phrase, now = new Date()) {
  const s = phrase.trim().toLowerCase()
  let m = s.match(/^(?:in )?(\d+)\s*(m|mins?|minutes?|h|hrs?|hours?)$/)
  if (m) return stamp(new Date(now.getTime() + Number(m[1]) * (m[2][0] === 'h' ? 3600e3 : 60e3)))
  m = s.match(/^(\d{4})-(\d{2})-(\d{2})(?: (\d{1,2}):(\d{2}))?$/)
  if (m) return stamp(new Date(m[1], m[2] - 1, m[3], m[4] || 9, m[5] || 0))
  m = s.match(/^(today|tomorrow)?\s*(?:at )?(?:(\d{1,2})(?::(\d{2}))?\s*(am|pm)?)?$/)
  if (!m || (!m[1] && !m[3] && !m[4])) return null
  let hour = m[2] ? Number(m[2]) : 9
  if (m[4] === 'pm' && hour < 12) hour += 12
  if (m[4] === 'am' && hour === 12) hour = 0
  const date = new Date(now.getFullYear(), now.getMonth(), now.getDate() + (m[1] === 'tomorrow' ? 1 : 0), hour, Number(m[3] || 0))
  if (!m[1] && date < now) date.setDate(date.getDate() + 1)
  return stamp(date)
}

const pad = n => String(n).padStart(2, '0')
const stamp = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`

// --- the local model (optional) ---

// Only a server on this Mac; anything else is ignored, so the plugin works without one.
function modelFor(settings) {
  const server = (settings.server || '').trim().replace(/\/+$/, '')
  if (!/^http:\/\/(127\.0\.0\.1|localhost|\[::1\]):\d+$/.test(server)) return null
  const ask = (system, user) => {
    const body = JSON.stringify({ model: settings.model || 'qwen2.5', stream: false, temperature: 0,
                                  response_format: { type: 'json_object' },
                                  messages: [{ role: 'system', content: system }, { role: 'user', content: user }] })
    const result = exec('/usr/bin/curl', ['-sS', '-m', '7', '-H', 'Content-Type: application/json', '--data-binary', '@-',
                                          server + '/v1/chat/completions'], body)
    try { return JSON.parse(JSON.parse(result.out).choices[0].message.content) } catch (e) { return null }
  }
  return {
    followUps(message, existing) {
      const answer = ask('You read the last message a coding agent wrote and list follow-up tasks it leaves for the developer: ' +
        'work explicitly left undone, next steps it suggests, or things the developer must check. Never list what the agent already did. ' +
        'Each task is one short imperative line under 80 characters. At most 3. Leave out tasks already in the backlog. ' +
        'Reply with JSON: {"tasks": ["..."]}, or {"tasks": []} if there are none.',
        'Already in the backlog:\n' + (existing.map(t => '- ' + t).join('\n') || '(nothing)') + '\n\nAgent message:\n' + message)
      return Array.isArray(answer && answer.tasks) ? answer.tasks.filter(t => typeof t === 'string').slice(0, 3) : []
    },
    reminder(prompt) {
      const answer = ask('The developer may be asking to be reminded of something, or to note a todo. Current local time: ' + stamp(new Date()) + '. ' +
        'Reply with JSON: {"task": "short imperative line", "at": "YYYY-MM-DD HH:MM" or null}, or {"task": null} if they are not asking for one.',
        prompt)
      if (!answer || typeof answer.task !== 'string' || !answer.task) return null
      let at = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(answer.at || '') ? answer.at : null
      if (at && at < stamp(new Date())) at = stamp(new Date(new Date(at.replace(' ', 'T')).getTime() + 864e5))
      return { text: answer.task, at }
    },
  }
}

// --- reminders in the notch ---

function sendDueReminders() {
  const lines = readLines()
  const now = stamp(new Date())
  const due = parse(lines).filter(item => !item.done && item.at && !item.sent && item.at <= now)
  due.forEach(item => {
    exec(NOTCHKEEPER, ['notify', '--source', 'backlog', '--id', idOf(item.text), '--title', item.text,
                       '--state', 'needs-you', '--detail', 'Reminder · ' + item.section])
    lines[item.index] = lines[item.index].replace(REMIND, ' (reminded ' + item.at + ')')
  })
  if (due.length) writeLines(lines)
}

function idOf(text) {
  let hash = 5381
  for (const c of text) hash = (hash * 33 + c.charCodeAt(0)) >>> 0
  return hash.toString(16)
}

// --- `notchkeeper todo` ---

function cli([verb, ...rest]) {
  if (verb === 'list') return list()
  if (verb === 'add') {
    let section = 'Inbox'
    const at = rest.indexOf('--repo')
    if (at >= 0) section = rest.splice(at, 2)[1] || section
    const task = splitWhen(rest.join(' '))
    if (!task.text.trim()) return fail('usage: notchkeeper todo add [--repo NAME] TEXT [at 3pm | in 20m | tomorrow]')
    const added = withLock(() => add(section, task.text, task.at))
    return added ? 'Added to ' + section + (task.at ? ', reminder ' + task.at : '') : 'Already in ' + section
  }
  if (verb === 'done') {
    const numbers = rest.map(Number)
    if (!numbers.length || numbers.some(n => !(n > 0))) return fail('usage: notchkeeper todo done N [N…]')
    return withLock(() => {
      const lines = readLines()
      const open = parse(lines).filter(item => !item.done)
      const picked = numbers.map(n => open[n - 1]).filter(Boolean)
      picked.forEach(item => {
        lines[item.index] = lines[item.index].replace('- [ ]', '- [x]')
        if (item.sent) exec(NOTCHKEEPER, ['notify', '--source', 'backlog', '--id', idOf(item.text), '--title', item.text, '--state', 'remove'])
      })
      writeLines(lines)
      return picked.map(item => 'Done: ' + item.text).join('\n') || 'No such item.'
    })
  }
  if (verb === 'edit') {
    if (!$.NSFileManager.defaultManager.fileExistsAtPath(FILE)) writeLines(readLines())
    exec('/usr/bin/open', ['-t', FILE])
    return
  }
  return fail('usage: notchkeeper todo [list | add TEXT | done N | edit]')
}

function list() {
  const open = parse(readLines()).filter(item => !item.done)
  if (!open.length) return 'Nothing in the backlog.'
  let section = null
  return open.map((item, i) => {
    const head = item.section !== section ? (section === null ? '' : '\n') + (item.section || 'Backlog') + '\n' : ''
    section = item.section
    return head + `  ${i + 1}. ${item.text}` + (item.at ? `  ⏰ ${item.at}` : '')
  }).join('\n')
}

// --- plumbing ---

function readStdin() {
  const data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile
  return $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js || '{}'
}

// Runs a program directly (no shell), feeding it input.
function exec(path, args, input) {
  const task = $.NSTask.alloc.init
  const stdin = $.NSPipe.pipe
  const stdout = $.NSPipe.pipe
  task.executableURL = $.NSURL.fileURLWithPath(path)
  task.arguments = $(args)
  task.standardInput = stdin
  task.standardOutput = stdout
  task.standardError = $.NSFileHandle.fileHandleWithNullDevice
  if (!task.launchAndReturnError(null)) return { code: -1, out: '' }
  if (input) stdin.fileHandleForWriting.writeData($(input).dataUsingEncoding($.NSUTF8StringEncoding))
  stdin.fileHandleForWriting.closeFile
  const data = stdout.fileHandleForReading.readDataToEndOfFile
  task.waitUntilExit
  return { code: task.terminationStatus, out: $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js || '' }
}

function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(2)
}
