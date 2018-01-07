# TODO: SWITCH TO TRANSACTIONS vs transaction null,
###
  'snooze': {}
'draft': {
  'send': {} # TODO
  'update': {} # TODO
  'delete': {} # TODO
}
'folder': {
  'rename': class
  'path': class
  'delete': class
}
###


# TODO: this file needs continue unless item.isValid()
Promise = require 'bluebird'
Promise.coroutine.addYieldHandler (yielded) ->
  Promise.all(yielded) if Array.isArray(yielded)
realm = require '../realm'
{ wrap } = require 'async-class'
CONSTANTS = require '../constants'
{ transaction } = require '../helpers'

# TODO: what happens to files when duplicates are preserved??
tasks = {}
tasks[CONSTANTS.OUTBOX.CONVERSATIONS] = {}
tasks[CONSTANTS.OUTBOX.CONVERSATIONS][CONSTANTS.ACTIONS.MOVE] = {
  waitForIMAP: true
  remote: (SyncEngine, task) ->
    Promise.coroutine(->
      foldermap = {}
      for conversation in task.conversations
        conversation.messages.filtered('folder.type != $0 && folder.type != $1 && folder.path != $2', CONSTANTS.FOLDER.SENT, CONSTANTS.FOLDER.DRAFTS, task.targetState)
        .snapshot()
        .map((message) ->
          foldermap[message.folder.path] ?= []
          foldermap[message.folder.path].push(message.uid)
        )
      for path, uids of foldermap
        { backend } = SyncEngine.accounts[task.account.address].engines[path]
        yield backend.moveMessages(path, uids, task.targetState) # NOTE: this backend function should attempt to batch in 1000s to avoid IMAP limits.
      return
    )()
  local: (task) ->
    targetFolder = realm.objects('Folder').filtered('account == $0 && path == $1', task.account, task.targetState).find(-> true)
    throw 'Moving conversations to unknown folder' if not targetFolder
    for conversation in task.conversations.snapshot()
      for message in conversation.messages.filtered('folder.type != $0 && folder.type != $1', CONSTANTS.FOLDER.SENT, CONSTANTS.FOLDER.DRAFTS).snapshot()
        message.tempFolder = targetFolder # todo: on fail target needs to be set back to IMAP.
    return
}
tasks[CONSTANTS.OUTBOX.CONVERSATIONS][CONSTANTS.ACTIONS.DELETE] = {
  waitForIMAP: false
  remote: (SyncEngine, task) ->
    Promise.coroutine(->
      foldermap = {}
      for conversation in task.conversations
        conversation.messages.filtered('deleted == false')
        .snapshot()
        .map((message) ->
          foldermap[message.folder.path] ?= []
          foldermap[message.folder.path].push(message.uid)
        )
      for path, uids of foldermap
        { backend } = SyncEngine.accounts[task.account.address].engines[path]
        yield backend.deleteMessages(path, uids) # NOTE: this backend function should attempt to batch in 1000s to avoid IMAP limits.
      return
    )()
  local: (task) ->
    for conversation in task.conversations
      conversation.deleted = true
    return
}
tasks[CONSTANTS.OUTBOX.CONVERSATIONS][CONSTANTS.ACTIONS.UNREAD] = {
  waitForIMAP: false
  remote: (SyncEngine, task) ->
    Promise.coroutine(->
      booleanState = task.targetState is '1'
      foldermap = {}
      for conversation in task.conversations
        conversation.messages.filtered('unread != $0', booleanState)
        .snapshot()
        .map((message) ->
          foldermap[message.folder.path] ?= []
          foldermap[message.folder.path].push(message.uid)
        )
      for path, uids of foldermap
        { backend } = SyncEngine.accounts[task.account.address].engines[path]
        yield backend.markMessages(path, uids, booleanState) # NOTE: this backend function should attempt to batch in 1000s to avoid IMAP limits.
      return
    )()
  local: (task) ->
    # TODO: for undo we can just reference message unread state to preserve as they wont change on offline anyway.
    for conversation in task.conversations
      conversation.unread = task.targetState is '1'
    return
}
tasks[CONSTANTS.OUTBOX.CONVERSATIONS][CONSTANTS.ACTIONS.SNOOZE] = {
  waitForIMAP: false
  remote: (SyncEngine, task) ->
    Promise.coroutine(->
      target = null
      if task.targetState[0] is 'M'
      	target = 'M'
      else if task.targetState[0] is 'D'
      	target = 'D'
      snoozedTo = new Date(parseInt(if target? then task.targetState[1...] else task.targetState)).getTime()
      foldermap = {}
      for conversation in task.conversations
        conversation.messages.snapshot()
        .map((message) ->
          foldermap[message.folder.path] ?= []
          foldermap[message.folder.path].push(message.uid)
        )
      for path, uids of foldermap
        { backend } = SyncEngine.accounts[task.account.address].engines[path]
        yield backend.snoozeMessages(path, uids, snoozedTo, target) # NOTE: this backend function should attempt to batch in 1000s to avoid IMAP limits.
      return
    )()
  local: (task) ->
    target = null
    if task.targetState[0] is 'M'
    	target = 'M'
    else if task.targetState[0] is 'D'
    	target = 'D'
    snoozedTo = new Date(parseInt(if target? then task.targetState[1...] else task.targetState))
    for conversation in task.conversations
      conversation.snoozed = true
      conversation.lastExchange.snoozedTo = snoozedTo
      ###
      for message in conversation.messages
        message.snoozedTo = snoozedTo
      ###
    return
}
tasks[CONSTANTS.OUTBOX.CONVERSATIONS][CONSTANTS.ACTIONS.PURGE] = {
  waitForIMAP: false
  remote: (SyncEngine, task) ->
    Promise.coroutine(->
      foldermap = {}
      conversations = realm.objects('Conversation').filtered('account == $0 && deleted == true && !(messages.tempFolder.type == 1 || messages.tempFolder.type == 5) && messages.tempFolder.type == 4', task.account).snapshot()
      for conversation in conversations
        conversation.messages.filtered('deleted == false && tempFolder.type != 4')
        .snapshot()
        .map((message) ->
          foldermap[message.folder.path] ?= []
          foldermap[message.folder.path].push(message.uid)
        )
      for path, uids of foldermap
        { backend } = SyncEngine.accounts[task.account.address].engines[path]
        yield backend.deleteMessages(path, uids) # NOTE: this backend function should attempt to batch in 1000s to avoid IMAP limits.
      { backend } = SyncEngine.accounts[task.account.address].engines[task.folder.path]
      yield backend.purgeFolder(task.folder.path)
      return
    )()
  local: (task) ->
    return if task.folder.type isnt 4
    # TODO: query should change based on `task.folder` that is being purged
    conversations = realm.objects('Conversation').filtered('account == $0 && !(messages.tempFolder.type == 1 || messages.tempFolder.type == 5) && messages.tempFolder.type == 4', task.account).snapshot()
    for conversation in conversations
      conversation.deleted = true
    return
}

# Unhandled rejection Error: Accessing object of type Outbox which has been deleted
class Outbox
  items: []
  running: false
  lastTask: null
  constructor: (@SyncEngine) ->
    dangling = realm.objects('Outbox').filtered('waitingForIMAP == true')
    if dangling.length > 0
      transaction null, ->
        realm.delete(dangling)
    @items = realm.objects('Outbox').sorted('timestamp') # TODO: we want the oldest first
    @items.addListener((collection, changes) =>
      if changes.insertions.length > 0 or changes.modifications.length > 0
        if changes.insertions.length > 0
          transaction null, =>
            # TODO: need to addm ore try catch blocks and properly report errors
            try
              for idx in changes.insertions
                item = @items[idx]
                continue unless item.isValid()
                tasks[item.target][item.type].local(item)
            catch err
              console.log err
      @run()
      return
    )
    @run()
    @SyncEngine.setOutboxHook(@syncHook)
  reset: =>
    dangling = realm.objects('Outbox').filtered('waitingForIMAP == true')
    if dangling.length > 0
      transaction null, ->
        realm.delete(dangling)
    @run()
    @SyncEngine.setOutboxHook(@syncHook)
  listDependencies: (item) =>
    dependencies = []
    hashmap = {}
    ids = item.conversations.snapshot().forEach(({ id }) ->
      hashmap[id] = true
    )
    potentialParents = @items.filtered('account == $0 && type == $1 && target == $2 && timestamp < $3', item.account, item.type, item.target, item.timestamp).snapshot()
    @dependencies = []
    for parent in potentialParents
      for id in parent.conversations
        if hashmap[id]?
          dependencies.push(parent)
          break
    [dependencies, hashmap]
  syncHook: (folder) =>
    console.log 'hook called..'
    # TODO issue with this
    removable = @items.filtered('account == $0 && waitingForIMAP == true && targetState == $1', folder.account, folder.path)
    if removable.length > 0
      realm.delete(removable)
  run: =>
    #return if not navigator.onLine
    #if not @running
      #@running = true
    for item in @items
      continue unless item.isValid()
      if not item.waitingForIMAP # TODO: need to restart runLoop when IMAP updates
        [dependencies, hashmap] = @listDependencies(item)
        if dependencies.length is 0
          @runTask(item, hashmap)
    return
  addTask: (task) =>
    transaction null, =>
      tasks[task.target][task.type].local(task)
      @items.push(task)
  undoTask: (task) =>
    # TODO: run local undo stuff, if remote has ran then need to push a new task
    transaction null, =>
      targetState = task.initialState
      task.initialState = task.targetState
      task.targetState = targetState
      task.timestamp = new Date()
  runTask: (task, hashmap) =>
    return if task.waitingForIMAP or not navigator.onLine # TODO: check IMAP connection
    try
      yield tasks[task.target][task.type].remote(@SyncEngine, task)
      transaction null, =>
        if tasks[task.target][task.type].waitForIMAP
          task.waitingForIMAP = true
        else
          realm.delete(task)
    catch err
      console.log err
      transaction null, =>
        if task.attempts >= 5
          console.log 'conflict resolution not complete'
          # TODO: update tasks that conflict
          ###
          dependencies = [] # just like dependency code but with no timestamp constraint

          hashmap = task.hashmap() # we can cache this from dependency checks!
          transaction null, =>
            for item in dependencies
              for conversation in item.conversations
                if hashmap[conversation.id]? # hmm, I feel like it might be redundant to run this after a dependency fetch...
                  realm.delete(conversation)
          ###
          realm.delete(task)
        else
          task.attempts++

module.exports = wrap Outbox
