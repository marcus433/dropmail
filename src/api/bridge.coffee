Promise = require 'bluebird'
{ ipcRenderer } = require 'electron'

publicProtocol = [
  'sendMessage'
  'saveDraft'
  'select'
  'createFolder'
  'deleteFolder'
  'renameFolder'
  'searchUids'
  'deleteConversations'
  'markConversations'
  'snoozeConversations'
  'moveConversations'
  'insertFiles'
  'streamFiles'
  'getBody'
  'status'
  'getInlineFiles'
]

class BackendBridge
  id: 0
  queue: {}
  constructor: ->
    for func in publicProtocol
      do (func) =>
        @[func] = (accountId, folderId, args...) =>
          @exec(accountId, folderId, func, args)
    ipcRenderer.on 'IMAPReciever', (ev, tag, resp) =>
      [accountId, folderId, func, args, resolve, reject] = @queue[tag]
      if resp.success
        resolve(resp.results...)
      else
        reject(new Error(resp.error))
      delete @queue[tag]
    ipcRenderer.on 'addAccountStatus', (ev, resp) =>
      if @newAccount?
        [resolve, reject] = @newAccount
        if resp.success
          resolve(resp)
        else
          reject(resp)
        delete @newAccount
    return
  addListener: (cb) =>
    ipcRenderer.on('IMAPListener', (e, args...) ->
      cb(args...)
    )
  exec: (accountId, folderId, func, args) =>
    new Promise (resolve, reject) =>
      tag = @id++
      @queue[tag] = [accountId, folderId, func, args, resolve, reject]
      ipcRenderer.send('IMAPWorker', tag, accountId, folderId, func, args)
  addAccount: (options) =>
    new Promise (resolve, reject) =>
      @newAccount = [resolve, reject]
      ipcRenderer.send('addAccount', options)

module.exports = new BackendBridge()
