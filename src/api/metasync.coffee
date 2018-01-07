LZString = require 'lz-string'
imap = require 'imap-client'
MailBuild = require 'emailjs-mime-builder'
MimeCodec = require 'emailjs-mime-codec'
database = require '../database'
Promise = require 'bluebird'
Lazy = require 'lazy.js'
config = {
  port: 993
  host: 'imap.gmail.com'
  secure: true
  ignoreTLS: false
  requireTLS: true
  auth: {
    pass: 'REDACTED'
    user: 'REDACTED'
  }
}
# TODO expunge issue
client = new imap(config)
client.onError = -> console.log arguments
 # MetaSync limits the user to 100 key value pairs maximum.
 # deletes are processed on uploads. dont upload for delete as it will eventually be resolved

 # If we do this another listener will be needed....
class MetaSync
  _metadata: {}
  _timeout: null
  snooze: true
  uidNext: 200
  syncingUid: null
  constructor: ->
    @load()
  set: (key, value) =>
    clearTimeout(@_timeout)
    @_metadata[key] = value
    @_timeout = setTimeout =>
      # flush
      raw = ''
      keys = Object.keys(@_metadata)
      for key,i in keys
        raw += "#{key}.#{@_metadata[key]}#{if keys.length is i+1 then '' else ','}"
      @commit(raw)
    , 1000
  get: (key) =>
  load: =>
    client.login()
    .then ->
      #client.createFolder({ path:'[DropMail]' })
      client.selectMailbox({ path:'[DropMail]/Preferences' })
    .then ({ uidNext, exists }) =>
      #TODO if exists is 0 then flush data from db to server
      Promise.reject(new Error('No changes or metadata folder is being abused')) if uidNext <= @uidNext or exists > 100 # only fetch if something new is available. This should hook into sync-store instead.
    .then ->
      # body.peek[TEXT]<0.100> to get preview content
      client._client.listMessages('1:*', ['uid', 'body.peek[1]', 'body.peek[header.fields (date)]'], {
        byUid: true
      })
    .then (messages) =>
      if messages.length > 0
        metadata = { timestamp:0 }
        invalidated = []
        for message in messages
          message.timestamp = (message['body[header.fields (date)]'] or '').replace(/^date:\s*/i, '').trim()
          message.timestamp = new Date(message.timestamp).getTime()
          if message.timestamp > metadata.timestamp
            invalidated.push(metadata.uid) if metadata.uid?
            metadata = message
          else
            invalidated.push(message.uid)
        @syncingUid = metadata.uid
        # TODO ranges should be used here..
        client._client.deleteMessages(invalidated.join(','), { byUid: true }) if invalidated.length > 0
        @_metadata = {}
        metadata = LZString.decompressFromUint8Array(MimeCodec.base64.decode(metadata['body[1]'])).split(',')
        uids = []
        for entry in metadata
          tuple = entry.split('.')
          if @snooze
            uid = parseInt(tuple[0])
            uids.push(uid)
            @_metadata[uid] = parseInt(tuple[1])
          else
            @_metadata[tuple[0]] = parseInt(tuple[1])
        if @snooze
          database.transaction (transaction) =>
            transaction('messagequery')
              .pluck('uid')
              .where(snooze:1,folderId:1,accountId:1)
              .select()
              .limit(100)
              .then (local) =>
                snoozed = Lazy(uids).without(local).toArray()
                unsnoozed = Lazy(local).without(uids).toArray()
                # TODO fix so the above dont provide data even when no changes are made. to fix use union.
                Promise.all([
                  Promise.map snoozed, (uid) =>
                    transaction('messagequery')
                      .where(uid:uid,folderId:1,accountId:1)
                      .limit(1)
                      .update(snoozed:@_metadata[uid])
                  Promise.map unsnoozed, (uid) =>
                    transaction('messagequery')
                      .where(uid:uid,folderId:1,accountId:1)
                      .limit(1)
                      .update(snoozed:0)
                ])
              .then -> transaction.commit()
      else
        console.log 'get from db and do commit'
  commit: (data) =>
    payload = LZString.compressToUint8Array(data)
    rootNode = new MailBuild()
    rootNode.setHeader({
      subject: 'DropMail Settings'
      from: 'DropMail@app'
      to: config.auth.user
      'content-type': 'application/dropmail-metadata; charset=us-ascii'
      'content-transfer-encoding': 'base64'
      'X-DM-Stamp': 'XYZ' # md5 checksum of compressed body
      'X-DM-Client': 'Some Arbitrary Hash unique to a client'
    })
    rootNode.setContent(payload)
    if @syncingUid?
      client._client.deleteMessages(@syncingUid, { byUid: true })
      .then =>
        client.uploadMessage({ path:'[DropMail]/Preferences', message:rootNode.build() })
    else
      client.uploadMessage({ path:'[DropMail]/Preferences', message:rootNode.build() })

module.exports = new MetaSync()
