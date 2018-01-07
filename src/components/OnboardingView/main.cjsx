require './_main.scss'
React = require 'react'
backend = require '../../api/bridge'
{ BrowserWindow } = require('electron').remote
electronOauth2 = require 'electron-oauth2'
fetch = require 'node-fetch'

config = {
  clientId: '771407356645-sndp43sjejl7ki9dssv8b7a05hab4q4p.apps.googleusercontent.com'
  clientSecret: 'JS_LGj87qQ7wXEXiDnwKrHhq'
  authorizationUrl: 'https://accounts.google.com/o/oauth2/v2/auth'
  tokenUrl: 'https://www.googleapis.com/oauth2/v4/token'
  useBasicAuthorizationHeader: false
  redirectUri: 'http://localhost'
}

addAccountOauth = ->
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

  oauthSession.getAccessToken({
    scope: 'email profile https://mail.google.com/'
    accessType: 'offline'
  }).then(({ access_token, refresh_token, expires_in }) ->
    ###
    myApiOauth.refreshToken(token.refresh_token)
      .then(newToken => {
        //use your new token
      });
    ###
    fetch('https://www.googleapis.com/plus/v1/people/me', { headers: { Authorization: "Bearer #{access_token}" } })
    .then((res) -> res.json())
    .then((profile) ->
      user = profile.emails[0].value
      name = profile.displayName ? null
      avatar = if not profile.image.isDefault then profile.image.url else null
      {
        pass: access_token
        refresh_token
        expires_in
        user
        name
        avatar
        oauth: true
      }
    )
  ).then((raw_accnt) ->
    backend.addAccount(raw_accnt)
  ).catch((resp) ->
    alert JSON.stringify(resp)
  )
login = null
LoginScreen = React.createClass
  displayName: "LoginScreen"
  getInitialState: ->
    show: false
  componentDidMount: ->
    login = (show) =>
      @setState({ show })
  addAccount: ->
    if not oauth
      backend.addAccount({ user: @refs.email.value, pass: @refs.password.value, name: @refs.name.value, oauth: false })
      .catch (resp) ->
        alert JSON.stringify(resp)
  render: ->
    <div className="login" style={if not @state.show then { display: 'none' } else {}}>
      <img src="https://logo.clearbit.com/gmail.com" height={@props.height}/>
      <paper-input label="Name" ref="name"></paper-input>
      <paper-input label="Email" ref="email"></paper-input>
      <paper-input label="Password" type="password" ref="password"></paper-input>
      <paper-button onClick={=> @addAccount()} raised>Add Account</paper-button>
    </div>

AccountChoice = React.createClass
  displayName: "AccountChoice"
  getInitialState: ->
    display: true
    selected: false
  onSetAccount: (id) ->
    window.requestAnimationFrame( =>
      @setState display: @props.id == id, selected: @props.id == id
    )
  onClick: ->
    #StateHandler.invokeAction "ChooseAccountProvider", [@props.id]
    ###
    if @props.src isnt 'gmail.com'
      return alert('This provider hasn\'t been enabled as this version of DropMail doesn\'t yet use oauth or encryption to secure logins')
    ###
    window.requestAnimationFrame( =>
      @setState display: true, selected: true
      if @props.src is 'gmail.com'
        addAccountOauth()
      else
        login(true)
    #login(true)
    )
  render: ->
    styles = {}
    styles = display: 'none' if not @state.display
    <div className="box#{if @state.selected then ' selected' else ''}#{if @props.popin then ' popin' else ''}" style=styles onClick={@onClick}>
      <img src="https://logo.clearbit.com/#{@props.src}" height={@props.height}/>
    </div>

OnboardingView = React.createClass
    displayName: "OnboardingView"
    getInitialState: ->
      lightenSlide: false
      popin: false
    componentDidMount: ->
      @setState lightenSlide: true, popin: true if @props.nosetup
    onClick: ->
      setTimeout => # material design timeout
        window.requestAnimationFrame( =>
          @setState lightenSlide: true
        )
      , 300
      setTimeout =>
        window.requestAnimationFrame( =>
          @setState popin: true
        )
      , 800
    render: ->
      slideState = if @state.lightenSlide then " lighten" else ""
      <div className="onboarding#{slideState}">
        <div className="window-controls mac">
          <div onClick={=> BrowserWindow.getFocusedWindow().close()}><img src="../static/images/close.svg"></img></div>
          <div onClick={=> BrowserWindow.getFocusedWindow().minimize()}><img src="../static/images/minimize.svg"></img></div>
          <div onClick={=> BrowserWindow.getFocusedWindow().setFullScreen(not BrowserWindow.getFocusedWindow().isFullScreen())}><img src="../static/images/fullscreen.svg"></img></div>
        </div>
        <div className="slide">
          <div className="header">
            <div className="title">{if @state.lightenSlide then "choose a provider" else "welcome friend"}</div>
            <div className="subtitle">Made With ❤︎ <span>By DropTech</span></div>
          </div>
          <div className="choose">
            <AccountChoice id={1} popin={@state.popin} src="gmail.com" height={50}></AccountChoice>
            <AccountChoice id={2} popin={@state.popin} src="outlook.com" height={60}></AccountChoice>
            <AccountChoice id={3} popin={@state.popin} src="yahoo.com" height={80}></AccountChoice>
            <AccountChoice id={4} popin={@state.popin}>IMAP</AccountChoice>
          </div>
        </div>
        <div className="action#{if @state.lightenSlide then ' hidden' else ''}" onClick={@onClick}>get started<paper-ripple fit></paper-ripple></div>
        <LoginScreen style={display: 'none'}></LoginScreen>
      </div>

module.exports = OnboardingView
