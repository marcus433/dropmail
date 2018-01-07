require './_main.scss'
require './redactor/redactor.css'
window.$ = window.jQuery = require 'jquery'
require './redactor/redactor.min'
React = require 'react'
ReactDOM = require 'react-dom'
debounce = null
require 'codemirror/lib/codemirror.css'
CodeMirror = require 'codemirror/lib/codemirror'
require 'codemirror/mode/htmlmixed/htmlmixed'
{ remote: { dialog, BrowserWindow } } = require 'electron'

Compose = React.createClass
  displayName: "OnboardingView"
  getInitialState: ->
    draft: false
    account: 0
    cfields: false
    to: []
    cc: []
    bcc: []
    users: []
  componentDidMount: ->
    $(@refs.body).redactor
      focus: true
      codemirror: true
      linebreaks: true
      tabifier: true
      toolbar: not @props.inline
      toolbarExternal: '.field:nth-of-type(4)'
      tabAsSpaces: 4
      dragImageUpload: false
      initCallback: ->
        #@insert.htmlWithoutClean('<div class="showMore"></div>')
        $('.redactor-box').append('<div class="showMore"></div>')
    CodeMirror.fromTextArea @refs.body,
      lineNumbers: true
      mode: 'htmlmixed'
      matchBrackets: true
      autoCloseBrackets: true
      lineWrapping: true
    highlightState = false # rather than this we will store it on items
    ###
    KeyboardStore.subscribe 'backspace', (backspace) =>
      if backspace
          refs = [@refs.to, @refs.cc, @refs.bcc]
          values = ['to', 'cc', 'bcc']
          index = refs.indexOf(document.activeElement)
          if index > -1
            ref = refs[index]
            if highlightState
              highlightState = false
              if ref.value.length is 0
                # TODO highlight before deleting
                @state[values[index]].pop()
                state = {}
                state[values[index]] = @state[values[index]]
                @setState state
            else
              highlightState = true
    KeyboardStore.subscribe ['enter', 'comma'], (enter) =>
      if enter
        refs = [@refs.to, @refs.cc, @refs.bcc]
        values = ['to', 'cc', 'bcc']
        index = refs.indexOf(document.activeElement)
        if index > -1
          ref = refs[index]
          @state[values[index]].push(ref.value)
          state = {}
          state[values[index]] = @state[values[index]]
          @setState state
          ref.value = ''
    if @props.inline
      AccountsStore.subscribe 'items', (items) =>
        @setState users: [items[@props.from]]
    else
      AccountsStore.subscribe 'items', (items) =>
        keys = Object.keys(items)
        @setState users: (items[key].user for key in keys)
    ###
  onSubject: ->
    @setState draft: true
  sampleparticipant: ->
    @setState test: true
  switchAccount: ->
    if @state.account+1 >= @state.users.length
      @setState account: 0
    else
      @setState account: @state.account+1
  attachFile: ->
    setTimeout =>
      dialog.showOpenDialog properties: ['openFile', 'openDirectory', 'multiSelections']
    , 300
  toggleCFields: ->
    $(@refs.toggle).slideToggle =>
      @setState cfields: not @state.cfields
  sendMail: ->
    # just for testing
    alert('SMTP support for sending is in development')
    styles = """
            <style>
              html, body {
                color: #697278 !important;
              }
              .dropmail-signature {
                color: #697278;
              }
            </style>
             """
    signature = """
                <div class='dropmail-signature'>
                  <br/>--<br/>
                  Sent from <a href='http://dropmailapp.com'>Dropmail</a>
                </div>
                """
    message =
      from: @state.users[@state.account]
      to: @state.to.join(',')
      subject: @refs.subject.value
      html: styles+$(@refs.body).redactor('code.get')+signature
    ###
    new SendMailTask(message: message, account: @state.users[@state.account])
    .then (response) =>
      @props.broadcastSent(response) if @props.broadcastSent?
    ###
    ###
      <div className="participant#{if @state.test then ' active' else ''}" onClick={@sampleparticipant}>
        <img src={"https://pbs.twimg.com/profile_images/2508434483/sk598n8o01bbz0horbw3_400x400.png"}/>
        Danielle
        <paper-icon-button icon="clear"></paper-icon-button>
      </div>
    ###
  render: ->
    <div className="compose#{if @props.inline then ' inline' else ''}" ref="compose">
      {
        if not @props.inline
          <div className="toolbar">
            <div className="window-controls mac">
              <div onClick={=> BrowserWindow.getFocusedWindow().close()}><img src="../static/images/close.svg"></img></div>
              <div onClick={=> BrowserWindow.getFocusedWindow().minimize()}><img src="../static/images/minimize.svg"></img></div>
              <div onClick={=> BrowserWindow.getFocusedWindow().setFullScreen(not BrowserWindow.getFocusedWindow().isFullScreen())}><img src="../static/images/fullscreen.svg"></img></div>
            </div>
            {if @state.draft then 'Message Draft' else 'New Message'}
            <div className="invisible"></div>
          </div>
      }
      <div className="container#{if @props.inline then ' inline' else ''}">
        <div className="field">
          <div className="name">To</div>
          <div className="participants">
            {
              for name in @state.to
                <div className="participant">
                  <img src={"https://logo.clearbit.com/#{name.split('@')[1]}"}/>
                  {name.split('@')[0]}
                </div>
            }
            <div className="participant">
              <img src={"https://logo.clearbit.com/dropmailapp.com"}/>
              DropMail
            </div>
          </div>
          <input ref="to"></input>
          <paper-icon-button icon="icons:arrow-drop-down" class="#{if @state.cfields then 'open' else ''} x-scope paper-icon-button-0" onClick={@toggleCFields}></paper-icon-button>
        </div>
        <div className="toggle#{if @state.cfields then ' open' else ''}" ref="toggle">
          <div className="field">
            <div className="name">Cc</div>
            <div className="participants">
              {
                for name in @state.cc
                  <div className="participant">
                    <img src={"https://logo.clearbit.com/#{name.split('@')[1]}"}/>
                    {name.split('@')[0]}
                  </div>
              }
            </div>
            <input ref="cc"></input>
          </div>
          <div className="field">
            <div className="name">Bcc</div>
            <div className="participants"></div>
            <input ref="bcc"></input>
          </div>
        </div>
        {
          subjectStyle = {}
          if @props.inline
            subjectStyle['display'] = 'none'
          <div className="field" style={subjectStyle}>
            <input placeholder="Subject" ref="subject" value={@props.subject} onKeyUp={@onSubject}></input>
          </div>
        }
        {
          if not @props.inline
            <div className="field"></div>
        }
        <textarea className="body" ref="body"></textarea>
        <div className="actions">
          <paper-icon-button icon="delete"></paper-icon-button>
          <paper-icon-button icon="attachment" onClick={@attachFile}></paper-icon-button>
          {
            if not @props.inline
              <span onClick={@switchAccount}>{@state.users[@state.account]}</span>
          }
          <paper-icon-button icon="send" onClick={@sendMail}></paper-icon-button>
        </div>
      </div>
    </div>

module.exports = Compose
