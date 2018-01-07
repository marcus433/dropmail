Promise = require 'bluebird'
Promise.coroutine.addYieldHandler (yielded) ->
  Promise.all(yielded) if Array.isArray(yielded)
imap = require 'emailjs-imap-client'
realm = require '../realm'
{ wrap } = require 'async-class'
{ sleep, transaction } = require '../helpers'
Backend = require '../backend'
FolderSync = require './foldersync'
OutboxSync = require './outboxsync'
AvatarSync = require './avatarsync'
SnoozeSync = require './snoozesync'
CONSTANTS = require '../constants'
keytar = require 'keytar'
electronOauth2 = require 'electron-oauth2'

SYNC_BATCH_LIMIT = 500 # TODO variables file so this isn't fragmented between foldersync and itself.

# TODO onError make new client etc
# proper is imap.gmail.com / imap.mail.yahoo.com

###
We use 4 IMAP clients at most.
- inbox[idle] (optional)
- sent[idle] (optional)
- action_client (required)
- sync_client[temporary] (optional)

SyncEngine will only fail sync is an action_client cannot be created.
No other cleints will trigger errors.
###

config = {
  clientId: '771407356645-sndp43sjejl7ki9dssv8b7a05hab4q4p.apps.googleusercontent.com'
  clientSecret: 'JS_LGj87qQ7wXEXiDnwKrHhq'
  authorizationUrl: 'https://accounts.google.com/o/oauth2/v2/auth'
  tokenUrl: 'https://www.googleapis.com/oauth2/v4/token'
  useBasicAuthorizationHeader: false
  redirectUri: 'http://localhost'
}

oauthSession = electronOauth2(config, {
  alwaysOnTop: true
  autoHideMenuBar: true
  width: 350
  height: 420
  frame: false
  webPreferences: {
    nodeIntegration: false
  }
})

class SyncEngine
  accounts: {}
  ready: false
  outbox: null
  setOutboxHook: (hook) =>
    for address, { engines } of @accounts
      for path, engine of engines
        engine.setHook(hook)
    return
  reset: (accounts) =>
    for account in realm.objects('Account').snapshot()
      continue unless account.isValid()
      yield @init(account)
    @outbox?.reset()
    @snooze?.run()
    #Tester = require('../sendmail')
    #new Tester(@)
    return
  cleanup: =>
    for address, account of @accounts
      yield @cleanupAccount(address, account)
    return
  cleanupAccount: (address, account) =>
    for folder, engine of account.engines
      try engine?.stop()
    for id, backend of account.backends
      try
        yield backend.client?.close()
      finally
        backend.client?.onupdate = null
        backend.client?.onerror = null
    for folder, client of account.idle
      try
        yield client?.close()
      finally
        client?.onupdate = null
        client?.onerror = null
    return
  constructor: ->
    window.addEventListener('online', => @reset())
    window.addEventListener('offline', @cleanup)
    @reset()
    @outbox = new OutboxSync(@)
    @snooze = new SnoozeSync(@)
    # TODO make this happen for modifications and deletions as well.
    realm.objects('Account').addListener (collection, changes) =>
      if changes.insertions.length > 0
        Promise.coroutine(=>
          for idx in changes.insertions
            continue unless accounts[idx].isValid()
            if not @accounts[accounts[idx].address]?
              yield @init(accounts[idx])
          @setOutboxHook(@outbox.syncHook)
          return
        )()
      if changes.deletions.length > 0
        addresses = realm.objects('Account').snapshot().map(({ address }) -> address)
        for address, account in @accounts
          if address not in addresses
            @cleanupAccount(address, account)
      return
  init: (account) =>
    @accounts[account.address] = {
      backends: {}
      idle: {}
      engines: {}
      client: null
      canIdle: null
    }
    if account.oauth
      refreshToken = keytar.getPassword('DropMail', account.address+'_refresh')
      try
        throw 'Missing Refresh Token' if not refreshToken?
        { access_token, expires_in } = yield oauthSession.refreshToken(refreshToken)
        keytar.replacePassword('DropMail', account.address, access_token)
      catch err
        { access_token, refresh_token, expires_in } = yield oauthSession.getAccessToken({
          scope: 'email profile https://mail.google.com/'
          accessType: 'offline'
        })
        keytar.replacePassword('DropMail', account.address, access_token)
        keytar.replacePassword('DropMail', account.address+'_refresh', refresh_token)
    pass = keytar.getPassword('DropMail', account.address)
    auth = { user: account.address, xoauth2: pass } # TODO: temporary
    @accounts[account.address].client = new imap('imap.gmail.com', 993, { auth, enableCompression: true })
    try
      yield @accounts[account.address].client.connect()
      @accounts[account.address].client.connected = true
    catch
      # TODO: should start retry attempts unless truly offline.
      try @accounts[account.address].client.close()
      throw new Error("Failed to connect to IMAP for: #{account.address}")
    @accounts[account.address].backends['ACTION_CLIENT'] = new Backend(account, @accounts[account.address].client)
    yield @accounts[account.address].backends['ACTION_CLIENT'].listFolders()

    if realm.objects('Folder').filtered('account == $0 && firstSync == false', account).length > 0
      syncClient = new imap('imap.gmail.com', 993, { auth, enableCompression: true })
      try
        yield syncClient.connect()
        syncClient.connected = true
        @accounts[account.address].backends['SYNC_CLIENT'] = new Backend(account, syncClient)

    @accounts[account.address].canIdle = if 'IDLE' in @accounts[account.address].client._capability then true else false
    if @accounts[account.address].canIdle
      @accounts[account.address].idle ?= { }
      @accounts[account.address].idle.Inbox = new imap('imap.gmail.com', 993, { auth, enableCompression: true })
      try
        yield @accounts[account.address].idle.Inbox.connect()
        @accounts[account.address].idle.Inbox.connected = true
        @accounts[account.address].idle.Inbox.onupdate = @onupdate.bind(undefined, account.address)
        @accounts[account.address].idle.Inbox.onerror = @onerror.bind(undefined, account.address)
      catch
        try yield @accounts[account.address].idle.Inbox.close()
        @accounts[account.address].idle.Inbox = null
      @accounts[account.address].idle.Sent = new imap('imap.gmail.com', 993, { auth, enableCompression: true })
      try
        yield @accounts[account.address].idle.Sent.connect()
        @accounts[account.address].idle.Sent.connected = true
        @accounts[account.address].idle.Sent.onupdate = @onupdate.bind(undefined, account.address)
        @accounts[account.address].idle.Sent.onerror = @onerror.bind(undefined, account.address)
      catch
        try yield @accounts[account.address].idle.Sent.close()
        @accounts[account.address].idle.Sent = null
    folders = realm.objects('Folder').filtered('account == $0', account).snapshot()
    priorities = folders.reduce ((p,c,i) -> p[+(c.type in [CONSTANTS.FOLDER.OTHER, CONSTANTS.FOLDER.ARCHIVE])].push c; p), [[],[]]
    batches = 0
    for folders in priorities
      for folder in folders
        continue unless folder.isValid()
        yield do (folder) =>
          Promise.coroutine( =>
            polling = false
            if folder.type is CONSTANTS.FOLDER.INBOX and @accounts[account.address].idle?.Inbox?
              client = @accounts[account.address].idle.Inbox
              @accounts[account.address].backends[folder.path] = new Backend(account, client)
            else if folder.type is CONSTANTS.FOLDER.SENT and @accounts[account.address].idle?.Sent?
              client = @accounts[account.address].idle.Sent
              @accounts[account.address].backends[folder.path] = new Backend(account, client)
            else
              polling = true
              client = @accounts[account.address].client
            folderBackend = @accounts[account.address].backends[folder.path] or @accounts[account.address].backends['ACTION_CLIENT']
            @accounts[account.address].engines[folder.path] = new FolderSync(polling, folder, folderBackend, @accounts[account.address].backends['SYNC_CLIENT'])
            yield @accounts[account.address].engines[folder.path].initialSync()
            folderBatches = Math.ceil(@accounts[account.address].engines[folder.path].uids.length / SYNC_BATCH_LIMIT)
            Promise.coroutine(=>
              while folderBatches--
                yield do (folder) =>
                  @accounts[account.address].engines[folder.path].incrementSync()
              return
            )()
            return
          )()
    return Promise.resolve()
  onupdate: (user, path, type, value) =>
    @accounts[user].engines[path].onIdle(type, value)
  onerror: (user) =>
  addAccount: ({ user, pass, refresh_token, name, expires_in, avatar, oauth }) =>
    user = user.toLowerCase()
    # TODO: set expiration timer to make new token. or convert it to timestamp and persist to account
    # TODO: check capabilities and make folders.
    existing = realm.objectForPrimaryKey('Account', user)
    return { success: false, error: 'Account already added.' } if existing?
    # TODO; store tempBackend as we can reuse it as the ACTION_CLIENT
    try
      tempBackend = new Backend(null, new imap('imap.gmail.com', 993, { auth: { user, xoauth2: pass }, enableCompression: true }))
      yield tempBackend.connect()
    catch err
      return { success: false, error: "Couldn\'t connect to account.", details: err.toString() }
    finally
      yield tempBackend.close()
      tempBackend = null
    try
      keytar.replacePassword('DropMail', user, pass)
      keytar.replacePassword('DropMail', user+'_refresh', refresh_token) if refresh_token?
    catch
      throw 'DropMail failed to save your password due to an unknown error.'
    account = null
    transaction(null, =>
      account = realm.create('Account', {
        address: user
        name: name
        avatar
        oauth
        configuration: JSON.stringify({})
      })
    )
    @init(account)
    return { success: true }
  getRealm: ->
    realm

module.exports = wrap SyncEngine
