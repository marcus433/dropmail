{ remote: { app } } = require 'electron'
Realm = require 'realm'
Alias = require './models/alias'
Account = require './models/account'
Contact = require './models/contact'
Folder = require './models/folder'
Message = require './models/message'
Conversation = require './models/conversation'
File = require './models/file'
Outbox = require './models/outbox'
Setting = require './models/setting'
module.exports = new Realm(
  path: app.getPath('userData')+"/dropmail.realm"
  schema: [Alias, Account, Contact, Folder, Message, Conversation, File, Outbox, Setting]
)
