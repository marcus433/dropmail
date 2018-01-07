realm = require '../realm'
{ wrap } = require 'async-class'
{ transaction } = require '../helpers'

# TODO add identifier tag DMSZ for quick uid check in FolderSync
# TODO max snooze timers?
class SnoozeSync
  running: false
  timers: []
  constructor: (@engine) ->
  reset: =>
    for timer in @timers
      clearTimeout(timer)
    @timers = []
    # TODO: have engine reset its link?
    return
  run: =>
    # TODO: make the below a hook into INBOX SYNC instead.
    # TODO: only if modseq doesn't match.
    for address, { backends } of @engine.accounts
      inbox = realm.objects('Folder').filtered('account.address == $0 && type == 1', address).find(-> true)
      continue unless inbox?.isValid()
      { flags } = yield backends['ACTION_CLIENT'].client.selectMailbox(inbox.path)
      now = new Date().getTime()
      removeFlags = []
      for flag in flags
        if flag.indexOf('DMSZ') is 0
          timestamp = parseInt(if flag[4] in ['M', 'D'] then flag[5...] else flag[4...])
          if not timestamp? or timestamp <= now # TODO ignore if its befoe last snozoeCheck TS
            removeFlags.push(flag)
          else
            @timers.push(setTimeout =>
              yield backends['ACTION_CLIENT'].wakeMessages(inbox.path, [flag])
              @timers.splice(0, 1)
            , new Date timestamp - new Date)
      yield backends['ACTION_CLIENT'].wakeMessages(inbox.path, removeFlags)
    @sync()
    return
  sync: =>
    # TODO: hook into sync cycle to pull latest snooze flags
    # TODO: does messages.snoozedTo > $0 imply all or only one must match?
    snoozed = realm.objects('Conversation').filtered('snoozed == true && messages.snoozedTo <= $0', new Date()).snapshot()
    # TODO: run outbox action to "unsnooze"

    # for testing purposes we will do the below
    if snoozed.length > 0
      transaction(null, =>
        for conversation in snoozed
          conversation.snoozed = false
        return
      )

module.exports = wrap SnoozeSync
