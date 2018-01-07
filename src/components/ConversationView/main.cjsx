require './_main.scss'
Promise = require 'bluebird'
React = require 'react'
ReactDOM = require 'react-dom'
backend = require '../../api/bridge'
Compose = require '../Compose/Main'
TimeNotation = require '../../utils/time-notation'
Lazy = require 'lazy.js'
RubberBand = require '../Rubberband/Main'
onClickOutside = require 'react-onclickoutside'
Store = require '../../store'
{ shell, remote: { app }, remote } = require 'electron'
FILES_PATH = app.getPath('userData')+'/files/'
realm = require '../../api/realm'
SwipeController = require '../../store/swipe'
AVATAR_PATH = app.getPath('userData')+'/avatars/'

# TODO: issues here when 0 items
Participant = onClickOutside React.createClass
  displayName: 'Participant'
  getInitialState: ->
    detailed: false
  onClick: ->
    @setState(detailed: true)
  handleClickOutside: ->
    # TODO, add 'popout' class for 100 ms or something and then set detailed: false
    @setState(detailed: false)
  render: ->
    { address, name, addressHash, cached } = @props.contact
    <div className="ptp-rel" onClick={@onClick}>
      <div className="participant #{if @state.detailed then 'active' else ''}">
        <div className="avatar #{if not cached then @props.tag else ''}" style={background:if cached then "url('#{AVATAR_PATH + addressHash}') no-repeat" else ''}>
          { if not cached then (name[0] or address[0]).toUpperCase() else '' }
        </div>
        <div className="name">{ name }</div>
        <div className="extra">
          <div className="ename">{address}</div>
          <paper-button onClick={=> Store.actions.compose()}>New Message</paper-button>
        </div>
      </div>
    </div>

frameClick = (event) ->
  event.preventDefault()
  href = @getAttribute('href')
  if href.indexOf('mailto:') is 0
    alert 'todo; will compose message'
  else
    remote.dialog.showMessageBox({
      type: 'none'
      message: 'Do you want to open this link?'
      detail: if href.length > 100 then href.slice(0,101)+'...' else href
      buttons: ['Open Link', 'Cancel']
    }, (idx) ->
      shell.openExternal(href) if not idx
    )

Message = React.createClass
  displayName: "Message"
  getInitialState: ->
    minimized: false
    url: null
    initials: null
  sizeFrame: ->
    window.requestAnimationFrame( =>
      message = @props.message
      messageId = message.id
      target = ReactDOM.findDOMNode(@refs["message-#{messageId}"])
      frame = ReactDOM.findDOMNode(@refs["body-#{messageId}"])
      target.style.height = 0 + 'px'
      frame.style.height = 0 + 'px'
      doc = frame.contentWindow.document
      # TODO figure out why it gets stuck sometimes
      target.style.height = doc.body.scrollHeight + 36 + 'px'
      frame.style.height = doc.body.scrollHeight + 'px'
    )
  shouldComponentUpdate: (props, state) ->
    props.message isnt @props.message or
    props.tag isnt @props.tag or
    props.message.from[0]?.cached isnt @props.message.from[0]?.cached
  toggleMinimize: ->
    ###
    return if @props.idx is 0 and @props.last
    @setState(minimized: not @state.minimized)
    ###
  componentDidMount: ->
    conversation = Store.collections.focus?[Store.selections.lastSelected]
    if conversation?.isValid()
      message = conversation.messages.filtered('id == $0', @props.message.id).find(-> true)
      backend.getInlineFiles(conversation.account?.address, message.folder?.path, @props.message.id)
      .then =>
        @writeMessageBody() # TODO
        console.log 'fetched attachments'
      .catch (err) ->
        console.log 'failed to fetch: ', err
  componentWillUnmount: ->
    frame = ReactDOM.findDOMNode(@refs["body-#{@props.message.id}"])?.contentDocument
    if @props.wheel? and not @props.message.draft
      frame.removeEventListener('wheel', @props.wheel)
    if frame?
      for element in frame.getElementsByTagName('a')
        element.removeEventListener('click', frameClick)
      frame.innerHTML = ''
      frame.src = 'about:blank'
    clearTimeout(@sizeFrame)
    if @props.message.draft
      for element in document.querySelectorAll('.redactor-toolbar-tooltip')
        element.parentElement?.removeChild(element)
      for element in document.querySelectorAll('.redactor-dropdown')
        element.parentElement?.removeChild(element)
  mergeFiles: (body) ->
    message = Store.collections.focus?[Store.selections.lastSelected]?.messages.filtered('id == $0', @props.message.id).find(-> true)
    for file in message.files
      if file.mimeType.indexOf('image') isnt 0 or file.size > 12 * 1024 * 1024
        body += """
                <div class=\"dropmail-inline-attachment\">
                  <div class=\"dropmail-attachment-preview\" mimeType=\"#{file.mimeType}\"></div>
                  <div class=\"dropmail-attachment-filename\">
                    #{file.filename ? '(No Name)'}
                  </div>
                  <div class=\"dropmail-attachment-size\">
                    #{Math.ceil(file.size / 1024)}kB
                  </div>
                </div>
                """
      else
        if file.saved
          if file.contentId?
            cidRegexp = new RegExp("cid:#{file.contentId}(['\"])", 'gi')
            body = body.replace cidRegexp, (text, quote) ->
              "#{FILES_PATH}#{file.id}#{quote}"
          else
            body += "<img src=\"#{FILES_PATH}#{file.id}\" class=\"dropmail-inline\" />"
        else
          inlineImgRegexp = new RegExp("<\s*img.*src=['\"]cid:#{file.contentId}['\"][^>]*>", 'gi')
          body = body.replace inlineImgRegexp, =>
            '<img alt="spinner.gif" src="" style="-webkit-user-drag: none;">'
    body.replace(new RegExp("src=['\"]cid:([^'\"]*)['\"]", 'g'), 'src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNikAQAACIAHF/uBd8AAAAASUVORK5CYII="')
  writeMessageBody: ->
    body = @props.message.body
    body = @mergeFiles(body)
    style =
    """
    <style>
    * {
      transition: .25s ease-in-out;
      -moz-transition: .25s ease-in-out;
      -webkit-transition: .25s ease-in-out;
    }
    html, body {
      font-family: Roboto-Regular;
      border: 0;
      -webkit-text-size-adjust: auto;
      word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space;
      line-height: 22px;
      font-size:15px;
      color: #1E1E1E;
      margin:0;
      padding:5px;
    }
    .gmail_extra {
      display: none !important;
    }
    .gmail_quote {
      display: none !important;
    }
    .mailbox_signature#mb-reply {
      display: block !important;
    }
    #orc-full-body-initial-text {
      display: none !important;
    }
    #orc-email-signature {
      display: none !important;
    }
    #psignature
    .dropmail_signature {
      display: none !important;
    }
    .dropmail-inline-link {
      margin-top: 10px;
      height: 40px;
      width: 300px;
      border-radius: 3px;
      border: 1px solid #CCC;
      font-size: 13px;
      font-family: Roboto-Medium;
      color: #1E1E1E;
    }
    .dropmail-inline-attachment {
      margin-top: 10px;
      height: 40px;
      width: 300px;
      border-radius: 3px;
      border: 1px solid #CCC;
      font-size: 13px;
      font-family: Roboto-Medium;
      color: #1E1E1E;
    }
    .dropmail-inline-attachment .dropmail-attachment-filename {
      //
    }
    .dropmail-inline-attachment .dropmail-attachment-preview {
      //
    }
    .dropmail-inline-attachment .dropmail-attachment-size {
      //
    }
    .dropmail-inline-attachment:hover {
      background: #CCC;
    }
    .dropmail-inline {
      display: block;
      width: 100%;
      height: auto;
      margin-top: 10px;
    }
    </style>
    """
    frame = ReactDOM.findDOMNode(@refs["body-#{@props.message.id}"])?.contentDocument
    frame.open()
    frame.write("<!DOCTYPE html>")
    frame.write("<meta id='dropmail-viewport' name='viewport' content='width=device-width, maximum-scale=2.0, user-scalable=yes'>")
    frame.write(style)
    frame.write(body)
    frame.close()
    # TODO: MAJOR, remove event listeners on loop & unmount.
    for element in frame.getElementsByTagName('a')
      element.removeEventListener('click', frameClick)
      element.addEventListener('click', frameClick)
    if @props.wheel?
      frame.removeEventListener('wheel', @props.wheel)
      frame.addEventListener('wheel', @props.wheel)
  mouseOver: ->
    @props.quickReply(false)
    setTimeout(@sizeFrame, 200) if not @props.message.draft
  mouseOut: ->
    @props.quickReply(true)
    setTimeout(@sizeFrame, 200) if not @props.message.draft
  fromAddress: ->
    { name, address, addressHash, cached } = @props.message.from[0]
    return { name: 'No Sender', address, addressHash, cached } if not @props.message.from[0]?
    if Store.global.state.accounts.length is 1
      account = Store.global.state.accounts[0]
      mes = [account?.address, account?.aliases.map(({ address }) -> address)...]
      if @props.message.from[0].address in mes
        return { name: 'Me', address, addressHash, cached  }
    name = @props.message.from[0].name
    return { name, address, addressHash, cached }
  render: ->
    { name, address, addressHash, cached } = @fromAddress()
    <div className="message#{if @state.minimized then ' minimized' else ''}" style={height: if @props.message.draft then 'auto' else 80} onMouseOver={=> @mouseOver()} onMouseOut={=> @mouseOut()} ref="message-#{@props.message.id}">
      {
        if @props.message.draft
          <Compose inline={true} />
        else
          <div className="message-details" onClick={@toggleMinimize}>
            {
              <div className="avatar #{if not cached then @props.tag else ''}" style={background:if cached then "url('#{AVATAR_PATH + addressHash}') no-repeat" else ''}>
                { if not cached then (name[0] or address[0]).toUpperCase() else '' }
              </div>
            }
            <div className="sender">{ name }</div>
            {
              ###
              if @props.message.cc.length > 0
                <div className="cc-label">CC</div>
                <div className="cc"> & {@props.message.cc.length} Others</div>
              ###
            }
            <div className="reply-message">
              <paper-icon-button icon="reply"></paper-icon-button>
              <paper-icon-button icon="reply-all"></paper-icon-button>
              <paper-icon-button icon="forward"></paper-icon-button>
            </div>
            <div className="timestamp"><div>{new TimeNotation(@props.message.timestamp or 0).state()}</div><div>{new TimeNotation(@props.message.timestamp or 0).replyFormat()}</div></div>
          </div>
      }
      {
        if not @props.message.draft
          setTimeout(@sizeFrame, 200)
          # TODO: break in to seperate iframe component?
          <iframe onLoad={=> @sizeFrame()} scrolling="no" className="conversation-body" ref="body-#{@props.message.id}"></iframe>
      }
    </div>

Messages = React.createClass
  displayName: 'Messages'
  verifiedUpdate: false
  getInitialState: ->
    messages: []
    lastSelected: 0
  componentDidMount: ->
    Store.collections.addListener 'messages', @refresh
    @refresh()
  componentDidUnmount: ->
    Store.collections.removeListener('messages', @refresh)
  shouldComponentUpdate: ->
    @verifiedUpdate or Store.collections.focus?[Store.selections.lastSelected]?.id isnt @state.lastSelected
  refresh: ->
    window.requestAnimationFrame( =>
      messages = []
      conversation = Store.collections.focus?[Store.selections.lastSelected]
      return unless conversation?.isValid()
      ###
      only call if changed.
      if conversation.unread
        realm.write =>
          realm.create('Outbox', {
            account: Store.global.state.accounts[0]
            type: 3
            target: 1
            initialState: '1'
            targetState: '0'
            timestamp: new Date()
            conversations: [conversation]
          })
      ###
      messages = conversation.messages.sorted('timestamp', true).snapshot()
      hashtable = {}
      for i in [0...messages.length]
        continue unless messages[i].isValid()
        hashtable[messages[i]['serverId']] = messages[i]
      messages = []
      for key, message of hashtable
        if message.body
          messages.push({
            timestamp: message.timestamp
            id: message.id
            from: message.from.map(({ address, name, addressHash, cached }) -> { address, name, addressHash, cached })
            body: message.body
            tag: message.tag
            serverId: message.serverId
            draft: message.folder?.type is 3
          })
        else
          backend.getBody(conversation.account?.address, message.folder?.path, message.id)
          null
      hashtable = null
      @verifiedUpdate = true
      @setState({ messages, lastSelected: conversation.id })
    )
  render: ->
    @verifiedUpdate = false
    conversation = Store.collections.focus?[Store.selections.lastSelected]
    if conversation?.isValid() and conversation.id isnt @state.lastSelected
      @refresh()
    <div className="messages-container">
      {
        for message, i in @state.messages
          # TODO: event bubbling should only be on elements in view
          <Message message={message} wheel={@props.wheel} quickReply={(state) => @props.quickReply(state)} tag={conversation?.tag} key={message.serverId} />
      }
    </div>

ConversationView = React.createClass
  displayName: "ConversationView"
  global: Store.global
  renderTimeout: null
  getInitialState: ->
    show: true
    hidden: false
    quickReply: true
    showFewParticipants: true
    scrolling: false
    snoozing: false
  componentDidMount: ->
  	Store.selections.addListener =>
      @prerender()
    Store.global.addListener (state, prop) =>
      folderType = Store.global.state.folder?.type or -1
      if folderType is 6
        @prerender()
    Store.actions.addListener('popover', @setPopoverState)
  prerender: ->
    clearTimeout(@renderTimeout)
    @renderTimeout = setTimeout =>
        window.requestAnimationFrame( =>
	         @forceUpdate()
        )
    , 100
  componentWillUnmount: ->
    Store.actions.removeListener('popover', @setPopoverState)
  setPopoverState: (type, orientation, boundingBox, callback) ->
    @setState(snoozing: boundingBox?)
  quickReply: (quickReply) ->
    @setState({ quickReply })
  toggleMoreParticipants: ->
    @setState({ showFewParticipants: not @state.showFewParticipants })
  scroll: ->
    @setState(scrolling: true) if not @state.scrolling
    clearTimeout(@scrolltimeout)
    @scrolltimeout = setTimeout =>
      @setState(scrolling:false)
    , 150
  snooze: ->
    SwipeController.setPosition(250)
    Store.actions.dispatch('popover', ['snooze', 'bottom', ReactDOM.findDOMNode(@refs['snooze']).getBoundingClientRect(), ->
      SwipeController.setPosition(0, 'RESET')
    ])
  render: ->
    hide = @global.state.folder?.type is 6
    selectionCount = Store.selections.count()
    conversation = Store.collections.focus?[Store.selections.lastSelected]

    conversation = null if not conversation?.isValid()
    me = null
    me = conversation.account?.address.toLowerCase() if conversation?
    ###
              <paper-icon-button icon="list" title="snooze"></paper-icon-button>
              <paper-icon-button icon="alarm" title="snooze"></paper-icon-button>
              <paper-icon-button icon="visibility" title="snooze"></paper-icon-button>
              <paper-icon-button icon="block" title="snooze"></paper-icon-button>
              <paper-icon-button icon="print" title="snooze"></paper-icon-button>
              <paper-icon-button icon="delete" title="trash"></paper-icon-button>
    ###
    <div className="conversation-view#{if not @state.show then ' hidden' else ''}" style={display: if hide then "none"}>
      {
        if selectionCount is 1
          styles = {
            snooze: {}
          }
          styles.snooze = { zIndex: 2000 } if @state.snoozing
          <div className="toolbar">
            <paper-icon-button icon="list" title="snooze" ref="snooze"></paper-icon-button>
            <paper-icon-button icon="alarm" title="snooze" style={styles.snooze} onClick={@snooze} ref="snooze"></paper-icon-button>
            <paper-icon-button icon="delete" title="trash" onClick={@delete}></paper-icon-button>
            <paper-icon-button icon="more-vert" title="trash"></paper-icon-button>
          </div>
      }
      <RubberBand class="conversation-wrapper#{if @state.scrolling then ' no-events' else ''}" onScroll={@scroll}>
        {
          # TODO complete the selections UI
          if selectionCount > 1
            <div className="state-wrapper">
              <div className="selectedCount">{selectionCount}</div>
              <div className="state">Conversations Selected</div>
              <div className="options">
                <paper-icon-button icon="list" title="snooze" ref="snooze"></paper-icon-button>
                <paper-icon-button icon="alarm" title="snooze"  onClick={@snooze}></paper-icon-button>
                <paper-icon-button icon="delete" title="trash"></paper-icon-button>
              </div>
            </div>
          else if selectionCount is 0
            <div className="state-wrapper">
              <div className="alldone"></div>
              <div className="state">{"You're all done"}</div>
            </div>
        }
        {
          if selectionCount is 1
            <div className="conversation-details">
              <div className="conversation-subject">{conversation?.subject}</div>
              <div className="conversation-participants">
                <div>
                  {
                    if conversation?
                      tag = ['social', 'personal', 'service', 'newsletter'][conversation.tag] or 0
                      # TODO: Remove replyTo
                      #ignore = conversation.messages.map((message) -> message.replyTo.snapshot()).map(({ hash }) -> hash)
                      count = 0
                      for participant in conversation.participants.snapshot()
                        { address, name, hash, addressHash, cached } = participant
                        if address isnt me
                          if @state.showFewParticipants
                            break if ++count is 4
                          <Participant contact={{ address, name, addressHash, cached }} tag={tag} key={hash}></Participant>
                  }
                  {
                    if conversation?.participants.length > 3
                      if @state.showFewParticipants
                        <div className="more" onClick={=> @toggleMoreParticipants()}>{"#{conversation.participants.length - 3} others"}</div>
                      else
                        <div className="more" onClick={=> @toggleMoreParticipants()}>{"Show #{conversation.participants.length - 3} less"}</div>
                  }
                </div>
              </div>
            </div>
        }
        {
          if selectionCount is 1
            <Messages wheel={@scroll} quickReply={@quickReply} />
        }
        {
          if selectionCount is 1
            <div className="quickreply #{if not @state.quickReply then 'hidden' else ''}">
              <iron-icon icon="create"></iron-icon>
              <div className="mini" ><iron-icon icon="reply"></iron-icon><paper-ripple className="circle recenteringTouch" fit></paper-ripple></div>
              <div className="mini"><iron-icon icon="reply-all"></iron-icon><paper-ripple className="circle recenteringTouch" fit></paper-ripple></div>
              <div className="mini"><iron-icon icon="forward"></iron-icon><paper-ripple className="circle recenteringTouch" fit></paper-ripple></div>
            </div>
        }
      </RubberBand>
    </div>

module.exports = ConversationView
