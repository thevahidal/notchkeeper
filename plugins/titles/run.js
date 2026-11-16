#!/usr/bin/osascript -l JavaScript
// Titles: names an agent from its first prompt with a local model.
ObjC.import('Foundation')

function run() {
  const event = JSON.parse(readStdin())
  const settings = event.settings || {}
  const session = event.session || {}
  const prompt = (event.prompt || '').trim()
  const firstLine = prompt.split('\n')[0].slice(0, 80)
  // Only while the title is still the default (repo name or the prompt itself), so it renames once.
  if (!prompt || (session.title !== session.repo && session.title !== firstLine)) return
  const title = ask(settings, 'Write a title of 3 to 6 words for a coding task, from the developer\'s request. ' +
    'Plain words, no quotes, no trailing period. Reply with JSON: {"title": "..."}', prompt)
  if (typeof title === 'string' && title.trim()) return JSON.stringify({ title: title.trim() })
}

// Only a server on this Mac; anything else is ignored.
function ask(settings, system, user) {
  const server = (settings.server || '').trim().replace(/\/+$/, '')
  if (!/^http:\/\/(127\.0\.0\.1|localhost|\[::1\]):\d+$/.test(server)) return null
  const body = JSON.stringify({ model: settings.model || 'qwen2.5', stream: false, temperature: 0,
                                response_format: { type: 'json_object' },
                                messages: [{ role: 'system', content: system }, { role: 'user', content: user }] })
  const out = exec('/usr/bin/curl', ['-sS', '-m', '7', '-H', 'Content-Type: application/json', '--data-binary', '@-',
                                     server + '/v1/chat/completions'], body)
  try { return JSON.parse(JSON.parse(out).choices[0].message.content).title } catch (e) { return null }
}

function readStdin() {
  const data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile
  return $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js || '{}'
}

function exec(path, args, input) {
  const task = $.NSTask.alloc.init
  const stdin = $.NSPipe.pipe
  const stdout = $.NSPipe.pipe
  task.executableURL = $.NSURL.fileURLWithPath(path)
  task.arguments = $(args)
  task.standardInput = stdin
  task.standardOutput = stdout
  task.standardError = $.NSFileHandle.fileHandleWithNullDevice
  if (!task.launchAndReturnError(null)) return ''
  stdin.fileHandleForWriting.writeData($(input).dataUsingEncoding($.NSUTF8StringEncoding))
  stdin.fileHandleForWriting.closeFile
  const data = stdout.fileHandleForReading.readDataToEndOfFile
  task.waitUntilExit
  return $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js || ''
}
