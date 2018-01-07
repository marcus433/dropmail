Realm = require '../api/realm'

# TODO account portion of the filtering should occur here.
class Collections
  folders: Realm.objects('Folder')
  accounts: Realm.objects('Account')
  conversations: Realm.objects('Conversation')
  messages: Realm.objects('Message')
  files: Realm.objects('File')
  focus: null
  listeners:
    folders: []
    accounts: []
    conversations: []
    messages: []
    files: []
    focus: []
  constructor: (@global) ->
    @setFocus()
    @global.addListener((state, prop) =>
      @setFocus() if prop isnt 'conversation'
    )
    @folders.addListener(=> @onChange('folders'))
    @accounts.addListener(=> @onChange('accounts'))
    @messages.addListener(=> @onChange('messages'))
    @conversations.addListener((collection, changes) =>
      # NOTE: there are so many modifications because realm relates children too.
      @onChange('conversations')
    )

    @files.addListener(=> @onChange('files'))
  onChange: (type) =>
    # hopefully no one used the snapshots...
    window.requestAnimationFrame( =>
      next = (idx) =>
        return if idx < 0
        try @listeners[type][idx]()
        next(--idx)
      next(@listeners[type].length - 1)
    )
  addListeners: (types, callback) =>
    for type in types
      @addListener(type, callback)
    return
  addListener: (type, callback) =>
    @listeners[type].push(callback)
  removeListener: (type, callback) =>
    idx = @listeners[type].indexOf(callback)
    @listeners[type].splice(idx, 1) if idx > -1
  setFocus: =>
    console.log @listeners
    filters = ['deleted == $0']
    values = [false]
    if @global.state.accounts?.length > 0
      accounts = []
      for account in @global.state.accounts
        accounts.push("account == $#{values.length}")
        values.push(account)
      filters.push('('+accounts.join(' || ')+')')
    if @global.state.unread
      filters.push('unread == true')
    if not @global.state.snoozed
      filters.push('snoozed == false')
    if @global.state.tag?
      filters.push("tag == $#{values.length}")
      values.push(@global.state.tag)
    if @global.state.folder
      if @global.state.folder.type is 1
        filters.push('messages.tempFolder.type == 1')
      else if @global.state.folder.type in [2, 3]
        filters.push("messages.tempFolder.type == $#{values.length}")
        values.push(@global.state.folder.type)
      else if @global.state.folder.type is 4
        filters.push('!(messages.tempFolder.type == 1 || messages.tempFolder.type == 5) && messages.tempFolder.type == 4')
      else if @global.state.folder.type is 5 or @global.state.folder.type is 7
        filters.push("messages.tempFolder.path == $#{values.length}")
        values.push(@global.state.folder.path)
    if @global.state.search? and @global.state.search.length > 0
      filters.push("(subject CONTAINS[c] $#{values.length} || participants.address CONTAINS[c] $#{values.length} || participants.name CONTAINS[c] $#{values.length})")
      values.push(@global.state.search)
    # TODO: new focus shouldnt dispatch if hasnt changed
    @focus.removeAllListeners() if @focus?
    @focus = @conversations
    @focus = @focus.filtered(filters.join(' && '), values...) if filters.length > 0
    @focus = @focus.sorted('timestamp', true)
    @onChange('focus')

module.exports = Collections
