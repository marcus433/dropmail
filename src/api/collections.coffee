Realm = require './realm'

class Collections
  constructor: (@account) ->
  folders: =>
    Realm.objects('Folder').filtered('account == $0', @account)
  conversations: =>
    Realm.objects('Conversation').filtered('account == $0', @account)
  messages: =>
    Realm.objects('Message').filtered('conversation.account == $0', @account)
  files: =>
    Realm.objects('File').filtered('message.conversation.account == $0', @account)

module.exports = Collections
