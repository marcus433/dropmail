realm = require './realm'
window.Promise = Promise = require 'bluebird'
Promise.coroutine.addYieldHandler (yielded) ->
  Promise.all(yielded) if Array.isArray(yielded)
{ wrap } = require 'async-class'
nodemailer = require 'nodemailer'
TimeNotation = require '../utils/time-notation'
juice = require 'juice'
Lazy = require 'lazy.js'
{ remote: { app } } = require 'electron'
FILES_PATH = app.getPath('userData')+'/files/'
fs = require 'fs'
util = require 'util'
mime = require 'mime'
engine = null

# TODO: how to version compose changes & attachments
class Draft
  type: null
  message: null
  alias: null
  account: null
  draft: null
  lastSaved: null
  constructor: (@draft, @type, @message, @alias, @account) ->
  setup: =>
    return if @draft?
    throw 'Failed to create draft.' if not @account?.isValid()
    if @type isnt 'new' and not @message.body?
      Backend = engine.accounts[@account.address].backends['ACTION_CLIENT']
      yield Backend.getBody(@message.id)
    if not @alias?
      @alias = @account
    if @type is 'forward'
      @stateForForward()
    else if @type isnt 'new'
      @reply()
    # TODO: trnsaction
    draftFolder = realm.objects('Folder').filtered('account == $0 && type == 3', @account).find(-> true)
    FolderSync = engine.accounts[@account.address].engines[draftFolder.path]
    realm.write =>
      [conversation] = FolderSync.messagesToConversations([Object.assign({}, {
        uid: -1
        id: Math.random().toString() # TODO; need a better standard than this
        from: [{ name: @alias.name, address: @alias.address }]
        sentDate: new Date()
        unread: false
        snoozedTo: null
        bodystructure: {}
        unsubscribe: null
        label: null
        replyTo: [{ name: @alias.name, address: @alias.address }]
        to: []
        cc: []
        bcc: []
        subject: ''
        references: []
        inReplyTo: null
        deleted: true
      }, @draft)], true)
      throw 'Failed to create draft.' if not conversation?.isValid()
      @draft = conversation.messages[conversation.messages.length - 1] # TODO: provide a better mechanism than this
      if @type is 'forward' and @message.files.length > 0
        @draft.files = @message.files # NOTE: this will be overriden on send.
  isMe: (address) => # NOTE: is this the proper handling of alias' for ME? or Should it only respond "me" to direct "from"
    if @alias.address is address
      return true
    for alias in @account.aliases
      if alias.address is address
        return true
    false
  reply: =>
    to = []
    cc = []
    if @type is 'reply'
      if @message.replyTo.length
        to = @message.replyTo
      else if @isMe(@message.from[0]?.address)
        to = @message.to
      else
        to = @message.from
    else if @type is 'reply-all'
      fromAddresses = @message.from.map(({ address }) => address)
      ccFilter = (addresses) =>
        addresses.filter(({ address }) => not @isMe(address) and address not in fromAddresses)
      if @message.replyTo.length
        to = @message.replyTo
        cc = ccFilter([@message.to..., @message.from...])
      else if @isMe(@message.from[0]?.address)
        to = @message.to
        cc = ccFilter(@message.cc)
      else
        to = @message.from
        cc = ccFilter([@message.to..., @message.cc...])
    to = Lazy(to).uniq('address').toArray()
    cc = Lazy(cc).uniq('address').toArray()
    references = [@message.references..., @message.messageId]
    inReplyTo = @message.messageId
    subject = "Re: #{@message.conversation.subject}"
    html = """
          <br><br>
          #{@alias.signature}
          <br>
          <div class="gmail_quote">
            <br>
            On #{new TimeNotation(@message.timestamp).replyFormat()}, #{@message.from[0]?.name ? ""} &lt;#{@message.replyTo[0]?.address ? @message.from[0]?.address}&gt; wrote:
            <br>
            #{@message.body}
          </div>
          """
    @draft = {
      body: juice(html)
      to
      cc
      subject: 'Re: ' + @message.conversation.subject
      references
      inReplyTo: inReplyTo
    }
  forward: =>
    formatContacts = (contacts) ->
      contacts.map(({ address, name }) -> "#{name} &lt;#{address}&gt;")
    fields = []
    fields.push("From: #{formatContacts(@message.from)}") if @message.from.length
    fields.push("Subject: #{@message.prefix}#{@message.conversation.subject}")
    fields.push("Date: #{new TimeNotation(@message.timestamp).replyFormat()}")
    fields.push("To: #{formatContacts(@message.to)}") if @message.to.length
    fields.push("Cc: #{formatContacts(@message.cc)}") if @message.cc.length
    html = """
          <br><br>
          #{@alias.signature}
          <br>
          <div class="gmail_quote">
            <br>
            ---------- Forwarded message ---------
            <br><br>
            #{fields.join('<br>')}
            <br><br>
            #{@message.body}
          </div>
          """
    @draft = {
      body: juice(html)
      subject: 'Fwd: ' + @message.conversation.subject
    }
  addFile: (path) =>
    uploadSize = 0
    for file in @draft.files
      uploadSize += file.size

    yield new Promise (resolve, reject) =>
      fs.stat(path, (err, stats) =>
        return reject(err) if err?
        return reject(new Error('File larger than 5 MB limit.')) if stats.size > 1000000 * 5
        return reject(new Error('Upload limit exceeds 15 MB. Please remove a file and try again.')) if ((1000000 * 15) - uploadSize) >= stats.size
        fs.createReadStream(path)
        .pipe(fs.createWriteStream(FILES_PATH + id))
        .on('error', => reject(new Error('Failed to upload file.')))
        .on('close', => resolve(id))
      )

    realm.write =>
      filename = null
      parts = path.split('/')
      @draft.files.push({
        id: 1 # TODO
        message: @draft
        mimeType: mime.lookup(filePath)
        contentId: null # TODO
        size: stats.size
        filename: parts[parts.length - 1]
      })
  removeFile: (file) =>
    # TODO: trnasaction
    @draft.files.splice(@draft.files.indexOf(file), 1)
    if file.message.id is @message.id
      realm.delete(file)
  convertToRFC: =>
    # TODO: syncengine should auto download body if it is a draft.
    # TODO; downlaods shouldn't show files from drafts
    rfc = {
      from: @draft.from.map(({ name, address }) -> { name, address })[0]
      to: @draft.to.map(({ name, address }) -> { name, address })
      cc: @draft.cc.map(({ name, address }) -> { name, address })
      bcc: @draft.bcc.map(({ name, address }) -> { name, address })
      subject: @draft.prefix + @draft.conversation.subject
      html: @draft.body
      messageId: @draft.messageId
      headers: { 'X-Mailer': 'DropMail' }
      references: @draft.references.split(' ')
      replyTo: @draft.replyTo[0].address
      # TODO: icalEvent
    }

    rfc.attachments = @draft.files.map(({ filename, mimeType, contentId }) ->
      file = {
        filename
        path: FILES_PATH + id
        contentType: mimeType
      }
      file.cid = contentId if contentId?
    )

    rfc.inReplyTo = @draft.inReplyTo if @draft.inReplyTo?
    rfc

Draft = wrap Draft

class SendMail
  transport: null
  constructor: (account) ->
    @transport = nodemailer.createTransport(JSON.parse(account.configuration))
  sendMail: (message) =>
    new Promise (resolve, reject) =>
      @transport.sendMail(message, (error, results) =>
        if error
          reject(error)
        else
          resolve(results)
      )
  send: (message) =>
    message.xMailer = false
    results = {}
    try
      console.log message
      results = yield @sendMail(message)
    catch error
      console.log error
      { rejected, pending, messageId } = results
      if (rejected and rejected.length > 0) or (pending and pending.length > 0)
        throw "Failed to send to at most #{(rejected.length ? 0)+(pending.length ? 0)} recipients."
      if error.message.startsWith('Invalid login: 535-5.7.8 Username and Password not accepted.')
        throw 'Failed to login. Please try again later.'
      throw 'Failed to send message.'

SendMail = wrap SendMail
#module.exports = wrap SendMail

###
Testing
###
class Tester
  constructor: (e) ->
    ###
    engine = e
    Promise.coroutine(->
      aDraft = new Draft(null, 'reply', realm.objects('Message').find(-> true), null, realm.objects('Account').find(-> true))
      yield aDraft.setup()
      draft = aDraft.convertToRFC()
      draft.to = draft.cc = draft.bcc = [{ name: 'Marcus Ferrario', address: 'marcusferr@sbcglobal.net' }]
      draft.text = draft.html
      new SendMail({ configuration: JSON.stringify({
        service: 'Gmail'
        auth: {
           user: '',
           pass: ''
        }
      })}).send(draft)
    )()
    ###

module.exports = Tester
