realm = require '../realm'

Promise = require 'bluebird'
md5 = require '../../utils/md5'
{ remote: { app } } = require 'electron'
AVATAR_PATH = app.getPath('userData')+'/avatars/'
{ transaction } = require '../helpers'
fs = require 'fs'
util = require 'util'
fetch = require 'node-fetch'

BATCH_SIZE = 50

class AvatarSync
  timeout: null
  firstRound: false
  constructor: ->
    fs.stat(AVATAR_PATH, (err) =>
      if err
        if err.code is 'ENOENT'
          fs.mkdir(AVATAR_PATH, @ready)
      else
        @ready()
    )
  ready: =>
    @processContacts()
  processContacts: =>
    clearTimeout(@timeout)
    return if not navigator.onLine
    @timeout = setTimeout(=>
      process.nextTick(=>
        if not @firstRound
          hashmap = {}
          contacts = []
          # NOTE: will this filter cause issues? .filtered('participants.cached == false')
          conversations = realm.objects('Conversation').filtered('participants.cached == false').sorted('timestamp', true)[0...BATCH_SIZE]
          for conversation in conversations
            for contact in conversation.participants.filtered('cached == false && uncacheable == false').sorted('rank', true).snapshot()
              if not hashmap[contact.addressHash]
                hashmap[contact.addressHash] = true
                contacts.push(contact)
          @firstRound = true if conversations.length > 0
        else
          contacts = realm.objects('Contact').filtered('cached == false && uncacheable == false').sorted('rank', true).snapshot()
        if not contacts.length
          realm.objects('Contact').addListener(@processContacts)
          return
        else
          realm.objects('Contact').removeListener(@processContacts)
        acceptedContacts = []
        rejectedContacts = []
        Promise.map(contacts[0...BATCH_SIZE], (contact) =>
          reject() if not contact.isValid()
          @fetch(contact.address, contact.addressHash)
          .then(-> acceptedContacts.push(contact))
          .catch(-> rejectedContacts.push(contact))
          .finally(-> Promise.resolve())
        ).then(=>
          return if not navigator.onLine
          transaction(null, =>
            # TODO: make more efficient
            for contact in acceptedContacts
              relatives = realm.objects('Contact').filtered('addressHash == $0 && cached == false && uncacheable == false', contact.addressHash).snapshot()
              for contact in relatives
                contact.cached = true
            for contact in rejectedContacts
              relatives = realm.objects('Contact').filtered('addressHash == $0 && cached == false && uncacheable == false', contact.addressHash).snapshot()
              for contact in relatives
                contact.uncacheable = true
            return
          )
          @processContacts()
        )
        return
      )
    , 5000)
  fetch: (address, addressHash) =>
    host = address.split('@')[1]
    parts = host.split('.')
    host = parts[parts.length - 2] + '.' + parts[parts.length - 1] if parts.length > 2
    if host is 'gmail.com' # TODO: match other common hosts, could also do DNS lookup potentially
      @reqGravatar(address, addressHash)
    else
      @reqClearbit(host, addressHash)
      .catch =>
        host = host.replace(/(email|mail|systems)/i, '') # TODO, only if at end, eg facebookmail.com -> facebook.com
        @reqClearbit(host, addressHash)
      .catch =>
        @reqGravatar(address, addressHash)
  reqGravatar: (address, addressHash) =>
    @reqBlob("https://secure.gravatar.com/avatar/#{md5(address)}?d=404&r=pg&s=200", addressHash)
  reqClearbit: (address, addressHash) =>
    @reqBlob("https://logo.clearbit.com/#{address}?s=128", addressHash)
  reqBlob: (url, addressHash) =>
    fetch(url)
      .then((res) =>
        new Promise((resolve, reject) =>
          return reject() if res.status is 404
          res.body.pipe(fs.createWriteStream(AVATAR_PATH + addressHash))
          .on('error', (err) => reject(err))
          .on('finish', => resolve(AVATAR_PATH + addressHash))
        )
      )

module.exports = new AvatarSync()
