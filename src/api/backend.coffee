realm = require './realm'
window.Promise = Promise = require 'bluebird'
Promise.coroutine.addYieldHandler (yielded) ->
  Promise.all(yielded) if Array.isArray(yielded)
mailreader = Promise.promisifyAll require 'mailreader'
utf7 = require 'emailjs-utf7'
Lazy = require 'lazy.js'
md5 = require '../utils/md5'
{ wrap } = require 'async-class'
Collections = require './collections'
CONSTANTS = require './constants'
sanitizeHtml = require 'sanitize-html'
{ minify } = require 'html-minifier'
fs = require 'fs'
{ remote: { app } } = require 'electron'
FILES_PATH = app.getPath('userData')+'/files/'
{ transaction, whereIn, sleep } = require './helpers'
`var getRanges = function(c) {
  for (var f = [], d, e, b = 0;b < c.length;b++) {
    for (e = d = c[b];1 == c[b + 1] - c[b];) {
      e = c[b + 1], b++;
    }
    f.push(d == e ? d + "," : d + ":" + e + ",");
  }
  return 0 < f.length ? f.slice(0, -1) : '';
}`

SanitizeSettings = {
  allowedTags: ["a", "abbr", "address", "area", "article", "aside", "audio", "b", "bdi", "bdo", "big", "blockquote", "body", "br", "button", "canvas", "caption", "cite", "code", "center", "col", "colgroup", "data", "datalist", "dd", "del", "details", "dfn", "dialog", "div", "dl", "dt", "em", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "i", "img", "input", "ins", "kbd", "keygen", "label", "legend", "li", "main", "map", "mark", "menu", "menuitem", "meta", "meter", "nav", "object", "ol", "optgroup", "option", "output", "p", "param", "picture", "pre", "progress", "q", "rp", "rt", "ruby", "s", "samp", "section", "select", "small", "source", "span", "strong", "sub", "summary", "style", "sup", "table", "tbody", "td", "textarea", "tfoot", "th", "thead", "time", "title", "tr", "track", "u", "ul", "var", "video", "wbr"],
  allowedAttributes: ['cellpadding', 'cellspacing', 'height', 'width', 'href', 'valign', 'align', 'alt', 'center', 'bgcolor', 'content', 'initialscale', 'maximumscale', 'user-scalable', 'abbr', 'accept', 'acceptcharset', 'accesskey', 'action', 'align', 'alt', 'async', 'autocomplete', 'axis', 'border', 'bgcolor', 'cellpadding', 'cellspacing', 'char', 'charoff', 'charset', 'checked', 'classid', 'classname', 'colspan', 'cols', 'content', 'contextmenu', 'controls', 'coords', 'data', 'datetime', 'defer', 'dir', 'disabled', 'download', 'draggable', 'enctype', 'form', 'formaction', 'formenctype', 'formmethod', 'formnovalidate', 'formtarget', 'frame', 'frameborder', 'headers', 'height', 'hidden', 'high', 'href', 'hreflang', 'htmlfor', 'httpequiv', 'icon', 'id', 'label', 'lang', 'list', 'loop', 'low', 'manifest', 'marginheight', 'marginwidth', 'max', 'maxlength', 'media', 'mediagroup', 'method', 'min', 'multiple', 'muted', 'name', 'novalidate', 'nowrap', 'open', 'optimum', 'pattern', 'placeholder', 'poster', 'preload', 'radiogroup', 'readonly', 'rel', 'required', 'role', 'rowspan', 'rows', 'rules', 'sandbox', 'scope', 'scoped', 'scrolling', 'seamless', 'selected', 'shape', 'size', 'sizes', 'sortable', 'sorted', 'span', 'spellcheck', 'src', 'srcdoc', 'srcset', 'start', 'step', 'style', 'summary', 'tabindex', 'target', 'title', 'translate', 'type', 'usemap', 'valign', 'value', 'width', 'wmode'],
  allowedSchemes: { indexOf: (scheme) -> (scheme isnt 'file') }
}

attributeMap = {}
for tag in SanitizeSettings.allowedTags
  attributeMap[tag] = SanitizeSettings.allowedAttributes
SanitizeSettings.allowedAttributes = attributeMap
# TODO add trigger to update conevrsations when messages are snoozed

class Backend
  constructor: (@account, @client) ->
    if process.env.NODE_ENV isnt 'development'
      @client.logLevel = @client.LOG_LEVEL_NONE
    @collections = new Collections(@account)
    # TODO setup nodemailer
    # attach on error to respawn from backendCluster
  connect: =>
    try
      throw 'Not connected' if not navigator.onLine
      if not @client.connected
        yield @client.connect()
      @client.connected = true
    catch
      @client.connected = false
      throw 'Not connected'
  close: =>
    @client.connected = false
    yield @client.close()
  errorResponse: =>
    # TODO https://tools.ietf.org/html/rfc5530, https://github.com/MailCore/mailcore2/blob/7eeb60a8b42cddcd4e61d299c8037cbb22eb63ba/src/core/imap/MCIMAPSession.cpp
  hasCapability: (capability) => capability in @client._capability
  dequeueOutbox: =>
    # TODO if action fails allow retry up to 3 with increasing intervals
    # we dont retry on normal errors as outbox should only correspond to offline activity
  saveDraft: =>
  select: (path) =>
    yield @connect()
    return yield @status(path) if @client._selectedMailbox is path
    mailbox = yield @client.selectMailbox(path)
    if mailbox.exists?
      { uidValidity, uidNext, highestModseq, exists } = mailbox
      { uidvalidity: uidValidity, uidnext: uidNext, highestmodseq: highestModseq, messages: exists }
    else
      yield @status(path)
  status: (path, options) =>
    yield @connect()
    options = options or {}
    attributes = ['UIDVALIDITY', 'UIDNEXT', 'MESSAGES']
    if 'CONDSTORE' in @client._capability or 'XYMHIGHESTMODSEQ' in @client._capability
      attributes.push('HIGHESTMODSEQ')
    response = yield @client.exec({
        command: 'STATUS',
        attributes: [{
          type: 'STRING'
          value: path
        }, attributes.map((attribute) =>
          {
            type: 'ATOM'
            value: attribute
          }
        )]
      }, 'STATUS', {
          precheck: (ctx) =>
            if @client._selectedMailbox is path
              Promise.resolve()
            else
              @client.selectMailbox(path, { ctx: ctx })
      })
    return if not response?.payload
    statusResponse = response.payload.STATUS[0] or []
    resp = {}
    for attribute, i in statusResponse.attributes[1]
      if i % 2 isnt 0
        key = statusResponse.attributes[1][i - 1].value.toLowerCase()
        value = attribute.value
        switch key
          when 'uidvalidity'
            value = Number(value) or 0
          when 'uidnext'
            value = Number(value) or 0
          when 'highestmodseq'
            value = value or '0'
          when 'messages'
            value = Number(value) or 0
        resp[key] = value
    return resp
  createFolder: (name, path) =>
    # TODO parent support
    folder = realm.objects('Folder').filtered('path == $0 && account == $1', path, @account).find(-> true)
    throw 'Folder already exists' if folder[0]?.isValid()
    yield @client.createMailbox(path)
    { uidNext, uidValidity, highestModseq } = yield @client.selectMailbox(path, { readOnly: true, condstore: true })
    transaction(null, =>
      realm.create('Folder', {
        type: CONSTANTS.FOLDER.OTHER
        path
        name
        uidNext
        uidValidity
        highestModseq
        firstSync: true
        account: @account
      })
    )
  deleteFolder: (path) =>
    yield @connect()
    folder = @collections.folders().filtered('path == $0', path).snapshot()
    if folder[0]?.isValid()
      folder = folder[0]
    else
      throw 'Folder does not exist.'
    yield @client.exec({
      command: 'DELETE',
      attributes: [utf7.imap.encode(folder.path)]
    }, 'DELETE', {}).catch (err) =>
      if err and err.code is 'NONEXISTENT'
        return
      throw err
    transaction(null, ->
      realm.delete(folder)
    )
  renameFolder: (path, newPath) =>
    yield @connect()
    folder = @collections.folders().filtered('path == $0', path).snapshot()
    if folder[0]?.isValid()
      folder = folder[0]
    else
      throw 'Folder does not exist.'
    yield @client.exec({
      command: 'RENAME',
      attributes: [utf7.imap.encode(path), utf7.imap.encode(newPath)]
    }, 'RENAME', {}).catch (err) =>
      if err and err.code is 'ALREADYEXISTS'
        return
      throw err
    transaction(null, ->
      folder.path = newPath
    )
  listFolders: =>
    yield @connect()
    root = yield @client.listMailboxes()
    existingPaths = @collections.folders().snapshot().map(({ path }) -> path)
    # TODO better guessing for folders... ex yahoo.
    specialUses = { '\\Trash': CONSTANTS.FOLDER.TRASH, '\\Sent': CONSTANTS.FOLDER.SENT, '\\Drafts': CONSTANTS.FOLDER.DRAFTS, '\\Archive': CONSTANTS.FOLDER.ARCHIVE, '\\All': CONSTANTS.FOLDER.ARCHIVE }
    ignore = ['\\Junk', '\\Flagged'] # \\Archive
    serverPaths = []
    folders = []
    format = (mailboxes) =>
      Promise.map mailboxes, ({ specialUse, subscribed, listed, path, name, delimiter, children, flags }) =>
        Promise.coroutine( =>
          # TODO: add logic so that all [Gmail] special folders are ignored
          # TODO: what if user already has folder named archive?
          # TODO: don't use [Gmail]/All Mail if \\Archive exists
          yield format(children) if children.length > 0
          if (not specialUse? or specialUse not in ignore) \
            and subscribed and listed and path not in existingPaths \
            and path isnt '[Gmail]/Important' \
            and path isnt '[Gmail]/Starred' and \
            not ('\\Noselect' in flags or '\\NoSelect' in flags or '\\NonExistent' in flags)
              hierarchy = path.split(delimiter) or []
              if specialUse is '\\All'
                if path isnt '[Gmail]/All Mail'
                  return
                if not @hasCapability('X-GM-EXT-1')
                  return
                hierarchy = ['Archive']
              folder = {
                name: hierarchy[hierarchy.length - 1]
                parent: if hierarchy.length > 1 then hierarchy[0...hierarchy.length - 1].join(delimiter) else null
                type: if name.toUpperCase() is 'INBOX' then CONSTANTS.FOLDER.INBOX else (specialUses[specialUse] or CONSTANTS.FOLDER.OTHER)
                path
                account: @collections.account
              }
              folders.push(folder)
          serverPaths.push(path)
        )()
    removed = []
    yield format root.children
    for path in existingPaths
      if path not in serverPaths
        removed.push(path)
    transaction(null, =>
      for folder in folders
        realm.create('Folder', folder)
      if removed.length > 0
        realm.delete(@collections.folders().filtered(whereIn('path', removed)))
    )
  listMessages: ({ path, sequence, byUid }, attributes) =>
    yield @connect()
    yield @client.listMessages(path, sequence, attributes, { byUid })
  labelResolver: (labels, type) ->
    resolvedTo = null
    level = 5
    for label in labels
      if label is '\\Sent' or type is CONSTANTS.FOLDER['SENT']
        if not resolvedTo? or 1 < level
          resolvedTo = CONSTANTS.FOLDER['SENT']
          level = 1
          break
      else if label is '\\Draft' or type is CONSTANTS.FOLDER['DRAFTS']
        if not resolvedTo? or 2 < level
          resolvedTo = CONSTANTS.FOLDER['DRAFTS']
          level = 2
      ###
      else if label is '\\Inbox'
        if not resolvedTo? or 3 < level
          resolvedTo = CONSTANTS.FOLDER['INBOX']
          level = 3
      ###
    resolvedTo
  fetchMessages: (options, type) =>
    query = ['uid', 'flags', 'envelope', 'internaldate', 'bodystructure', 'body.peek[header.fields (references)]', 'body.peek[header.fields (list-unsubscribe)]']
    #query.push('modseq') if @hasCapability('CONDSTORE') or @hasCapability('XYMHIGHESTMODSEQ')
    query.push('X-GM-LABELS') if @hasCapability('X-GM-EXT-1')
    messages = yield @listMessages(options, query)
    boundOn = if options.byUid then 'uid' else '#'
    doesBound = -> true
    if options.bounds.low? and options.bounds.high?
      doesBound = (message) -> message[boundOn] >= options.bounds.low and message['uid'] < options.bounds.high
    else if options.bounds.low?
      doesBound = (message) -> message[boundOn] >= options.bounds.low
    else if options.bounds.high?
      doesBound = (message) -> message['uid'] < options.bounds.high
    Lazy(messages)
    .filter((message) ->
      !!message.uid and doesBound(message)
    )
    .map((message) =>
      labels = message['x-gm-labels'] or []
      label = @labelResolver(labels, type)
      references = (message['body[header.fields (references)]'] || '').replace(/^references:\s*/i, '').trim()
      unsubscribe = (message['body[header.fields (list-unsubscribe)]'] || '').toLowerCase().replace(/^list-unsubscribe:\s*/i, '').trim()
      flags = message.flags or []
      unread = true
      snoozedTo = null
      for flag in flags
        if flag is '\\Seen'
          unread = false
        else if flag.indexOf('DMSZ') is 0
          mobile = false
          desktop = false
          if flag[4] is 'M'
          	mobile = true
          else if flag[4] is 'D'
          	desktop = true
          # TODO: need to store destination state: [Mobile, Desktop]
          snoozeTimestamp = parseInt(flag.replace(/\D+/g, '')) or 0
          if not snoozedTo? or snoozeTimestamp > snoozedTo
            snoozedTo = new Date(snoozeTimestamp)
      resolveDate = (sentDate, internalDate) ->
        d = null
        if sentDate
          d = new Date(sentDate)
        if not d or not d.getTime()
          d = new Date(internalDate)
        d
      {
        uid: message.uid
        id: (message.envelope['message-id'] or '').replace(/[<>]/g, '')
        from: message.envelope.from or []
        replyTo: message.envelope['reply-to'] or []
        to: message.envelope.to or []
        cc: message.envelope.cc or []
        bcc: message.envelope.bcc or []
        subject: message.envelope.subject or '(no subject)'
        sentDate: resolveDate(message.envelope.date, message.internaldate)
        unread
        snoozedTo
        bodystructure: message.bodystructure
        references: if references? then references.split(/\s+/).map((reference) -> reference.replace(/[<>]/g, '')) else []
        unsubscribe: if unsubscribe? then unsubscribe.split(/\s+/).map((unsubscribe) -> unsubscribe.replace(/[<>]/g, ''))[0] else null # TODO: only store 1 for now.
        label
        inReplyTo: message.envelope['in-reply-to']
      })
      .toArray()
  modseqs: ({ path, highestmodseq }, sequence) =>
    yield @connect()
    yield @client.listMessages(path, sequence, ['uid', 'flags', 'modseq'], {
      byUid: true,
      changedSince: highestmodseq
    })
  uids: (path, query) =>
    yield @connect()
    yield @client.search(path, query, { byUid: true })
  searchUids: (path, query) =>
    # TODO handle UID SEARCH not allowed now.
    yield @uids(path, { text: query })
  seqForUid: (path, uid) =>
    yield @connect()
    messages = yield @client.listMessages(path, uid, ['uid'], { byUid: true })
    throw 'Doesn\'t exist' if messages.length is 0
    messages[0]['#']
  uidForSeq: (path, seq) =>
    yield @connect()
    messages = yield @client.listMessages(path, seq, ['uid'])
    throw 'Doesn\'t exist' if messages.length is 0
    messages[0]['uid']
  moveMessages: (path, uids, target) =>
    yield @connect()
    batch = uids # TODO: add batching? or can server handle it
    yield @client.moveMessages(path, batch.join(','), target, byUid: true)
  deleteMessages: (path, uids) =>
    yield @connect()
    batch = uids # TODO: add batching? or can server handle it
    yield @client.deleteMessages(path, batch.join(','), byUid: true)
  purgeFolder: (path) =>
    yield @connect()
    yield @client.deleteMessages(path, '1:*')
  snoozeMessages: (path, uids, timestamp, target) =>
    yield @connect()
    batch = uids # TODO: add batching? or can server handle it
    flag = 'DMSZ'
    flag += target if target? # target is either M or D
    flag += timestamp
    sequence = batch.join(',')
    yield @client.setFlags(path, sequence, set: [flag, 'DMSZ'], { byUid: true, silent: true })
  wakeMessages: (path, flags) =>
    # TODO: what about server portion of "waking"
    yield @connect()
    yield @client.setFlags(path, '1:*', remove: [flags..., 'DMSZ'], { byUid: true, silent: true })
  markMessages: (path, uids, unread) =>
    yield @connect()
    batch = uids # TODO: add batching? or can server handle it
    if unread
      yield @client.setFlags(path, batch.join(','), remove: ['\\Seen'], { byUid: true, silent: true })
    else
      yield @client.setFlags(path, batch.join(','), set: ['\\Seen'], { byUid: true, silent: true })
  getBodyparts: (uid, path) =>
    yield @connect()
    matches = yield @client.listMessages(path, uid, ['bodystructure'], { byUid: true })
    throw 'Server error.' if matches.length is 0
    bodystructure = matches[0].bodystructure
    throw 'Server error.' if not bodystructure?
    bodyParts = []
    files = []
    walkBodyPart = ({ type, part, parameters, disposition, dispositionParameters, size, contentId, childNodes }) ->
      return if not type?
      if /^multipart\//i.test(type)
        if childNodes and Array.isArray(childNodes)
          for child in childNodes
            walkBodyPart(child)
        return

      params = parameters
      dispParams = dispositionParameters
      id = contentId

      if /^text\/plain/i.test(type) and disposition isnt 'attachment'
        return bodyParts.push(type: 'text', partNumber: part or 1)
      if /^text\/html/i.test(type) and disposition isnt 'attachment'
        return bodyParts.push(type: 'html', partNumber: part or 1)

      filename = null

      if dispParams and dispParams.filename
        filename = dispParams.filename
      else if params and params.name
        filename = params.name

      filename = null if filename? and filename.replace(/\s+/g, ' ').trim() is ''

      return if disposition not in ['inline', 'attachment'] and disposition?
      pushFile = ->
        files.push({
          partNumber: part or ''
          mimeType: type or 'application/octet-stream'
          contentId: if id then id.replace(/[<>]/g, '') else undefined
          size: parseInt(size) or null
          filename
        })
      if disposition is 'attachment'
        return pushFile()
      if disposition is 'inline' and not (filename and id)
        bodyParts.push(type: 'inline', partNumber: part or '')
      return pushFile()
    walkBodyPart(bodystructure)
    return { bodyParts, files }
  getFiles: (bodystructure, message) =>
    return [] if not bodystructure?
    files = []
    walkBodyPart = ({ type, part, parameters, disposition, dispositionParameters, size, id, childNodes }) ->
      return if not type?
      if /^multipart\//i.test(type)
        if childNodes and Array.isArray(childNodes)
          for child in childNodes
            walkBodyPart(child)
        return
      params = parameters
      dispParams = dispositionParameters

      filename = null

      if dispParams and dispParams.filename
        filename = dispParams.filename
      else if params and params.name
        filename = params.name

      return if /^text\/plain/i.test(type) and disposition isnt 'attachment'
      return if /^text\/html/i.test(type) and disposition isnt 'attachment'

      return if disposition not in ['inline', 'attachment'] and disposition?

      filename = undefined if filename? and filename.replace(/\s+/g, ' ').trim() is ''
      pushFile = ->
        files.push({
          partNumber: if part? then "#{part}" else undefined
          mimeType: type or 'application/octet-stream'
          contentId: if id then id.replace(/[<>]/g, '') else undefined
          size: parseInt(size) or 0
          filename
          message
        })
      return pushFile()
    walkBodyPart(bodystructure)
    return files
  streamFiles: (id) =>
    # TODO if Array(id).isArray() then whereIn else where
    { partNumber, message, filename } = file = realm.objects('File').filtered('id == $0', id)[0]
    [ { content, type } ] = yield @streamBodyparts(message.folder.path, message.uid, [{ partNumber, type: 'attachment' }])
    # TODO add md5 when saving to dedupe on hard-drive
    yield @fileUrl(file, content) # NOTE on reset remember to clear downloads cache
    # TODO yield
  fileUrl: (file, content) =>
    yield new Promise (resolve, reject) =>
      fs.writeFile(FILES_PATH + file.id, content, (err) =>
        return reject(err) if err
        try
          transaction(null, =>
            file.saved = true
            resolve()
          )
        catch err
          reject(err)
      )
  streamBodyparts: (path, uid, bodyParts) =>
    yield @connect()
    partTypes = {}
    partNumbers = []
    for { type, partNumber } in bodyParts
      partTypes[partNumber] = type
      partNumbers.push("body.peek[#{partNumber}.mime]")
      partNumbers.push("body.peek[#{partNumber}]")
    return [] if partNumbers.length is 0
    bodyParts = yield @client.listMessages(path, uid, partNumbers, { byUid: true })
    bodyParts = Object.keys(partTypes).map (partNumber) ->
      raw = bodyParts[0]["body[#{partNumber}.mime]"] + bodyParts[0]["body[#{partNumber}]"]
      type = partTypes[partNumber]
      { raw, type, partNumber }
    yield mailreader.parseAsync { bodyParts }
  getBody: (messageId) =>
    # TODO: for some reason this gets called "infinitely" sometimes...
    message = realm.objectForPrimaryKey('Message', messageId)
    throw 'Message deleted.' if not message?.isValid()
    body = message.body
    folderPath = message.folder.path
    uid = message.uid
    return body if body and body.length > 0
    { bodyParts } = yield @getBodyparts(uid, folderPath)
    textParts = []
    htmlParts = []
    inlineParts = []
    for part, idx in bodyParts
      { type } = part
      if type is 'html'
        htmlParts.push(part)
      else if type is 'inline'
        inlineParts.push({ type: 'attachment', partNumber: bodyParts[idx].partNumber })
      else if type is 'text'
        textParts.push(part)
    bodyParts = if htmlParts.length > 0 then htmlParts else textParts
    bodyParts = yield @streamBodyparts(folderPath, uid, bodyParts)
    if htmlParts.length is 0
      bodyParts = bodyParts.concat(inlineParts).sort (x, y) ->
        a = x.partNumber
        b = y.partNumber
        segmentsA = a.replace(/(\.0+)+$/, '').split('.')
        segmentsB = b.replace(/(\.0+)+$/, '').split('.')
        l = Math.min(segmentsA.length, segmentsB.length)
        for i in [0...l]
          diff = parseInt(segmentsA[i], 10) - parseInt(segmentsB[i], 10)
          return diff if diff
        segmentsA.length - segmentsB.length
    body = ''
    transaction(null, =>
      for { content, type, partNumber, id } in bodyParts
        if type is 'html'
          body += content
        else if type is 'text'
          charEncodings =
            '\t': '&nbsp;&nbsp;&nbsp;&nbsp;'
            ' ': '&nbsp;'
            '&': '&amp;'
            '<': '&lt;'
            '>': '&gt;'
            '\n': '<br />'
            '\r': '<br />'
          space = /[\t ]/
          noWidthSpace = '&#8203;'
          content = content.replace(/\r\n/g, '\n')
          html = ''
          lastChar = ''
          for char, i in content
            charCode = content.charCodeAt(i)
            if space.test(char) and not space.test(lastChar) and space.test(content[i + 1] or '')
              html += noWidthSpace
            html += if char in Object.keys(charEncodings) then charEncodings[char] else (if charCode > 127 then "&##{charCode};" else char)
            lastChar = char
          urlPattern = /\b(?:https?|ftp):\/\/[a-z0-9-+&@#\/%?=~_|!:,.;]*[a-z0-9-+&@#\/%=~_|]/gim
          pseudoUrlPattern = /(^|[^\/])(www\.[\S]+(\b|$))/gim
          emailAddressPattern = /\w+@[a-zA-Z_]+?(?:\.[a-zA-Z]{2,6})+/gim
          html = html.replace(urlPattern, '<a href="$&" class="dropmail-inline-link">$&</a>')
                     .replace(pseudoUrlPattern, '$1<a href="http://$2" class="dropmail-inline-link">$2</a>')
                     .replace(emailAddressPattern, '<a href="mailto:$&" class="dropmail-inline-link">$&</a>')
          body += html
        else if type is 'attachment'
          contentId = null
          contentId = id if id?
          if not contentId?
            file = message.files.filtered('partNumber == $0', partNumber).find(-> true)
            if file?
              contentId = file.contentId if file.contentId?
              contentId = Math.random().toString(36).substring(7)
            file.contentId = contentId
          body += "<img src=\"cid:#{contentId}\" class=\"dropmail-inline\" />" # NOTE could inline be text?
      body = sanitizeHtml(body, SanitizeSettings)
      body = minify(body, {
        collapseInlineTagWhitespace: true
        collapseWhitespace: true
        conservativeCollapse: true
        minifyCSS: true
        removeComments: true
        removeRedundantAttributes: true
        useShortDoctype: true
      })
      # TODO parse quotes
      if message?.isValid()
        body = ' ' if body.length is 0
        message.body = body
      else
        throw 'Message deleted.'
    )
    return body
  getInlineFiles: (messageId) =>
    message = realm.objectForPrimaryKey('Message', messageId)
    return if not message?.isValid()
    for file in message.files
      continue unless file.isValid()
      if not file.saved and file.mimeType.indexOf('image') is 0 and file.size <= 12 * 1024 * 1024
        yield @streamFiles(file.id)
    return null

module.exports = wrap Backend
