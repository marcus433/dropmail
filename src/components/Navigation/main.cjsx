require './_main.scss'
React = require 'react'
Realm = require '../../api/realm'
Store = require '../../store'
Lazy = require 'lazy.js'
{ BrowserWindow, app } = require('electron').remote

# TODO: keycodes when pressing command/control
FolderParent = React.createClass
  displayName: "FolderParent"
  getInitialState: ->
    open: false
    count: 0
  onClick: ->
    # TODO: this should actually be done by id to avoid acount being necessary...
    Object.assign(Store.global.state, { tag: null, folder: @props.folder[1][0] })
    @setState open: !@state.open
  componentDidMount: ->
    # TODO: Store.collections.addListener 'folders', =>
    count = 0
    # TODO: find better way to do below.
    count += Realm.objects('Conversation').filtered('messages.folder.path == $0', folder.path).length for folder in @props.folder[1]
    @setState count: count
  shouldComponentUpdate: (props, state) ->
    state isnt @state or
    @props.folder[1].length isnt props.folder[1].length
  render: ->
    <li style={display:if @state.count > 0 then 'block' else 'none'}>
      <div className={if @state.open then 'active' else ''} onClick={@onClick}>
        <span className={if @state.open then 'open' else ''} style={opacity:@props.folder[1].length-1}>
          <iron-icon icon="icons:arrow-drop-down"></iron-icon>
        </span>
        {@props.folder[0]}
      </div>
      <div className={if @state.open then 'active' else ''}>{if @props.folder[1].length > 0 then 'EDIT' else ''}</div>
    </li>

NavItem = React.createClass
  displayName: 'NavItem'
  global: Store.global
  shouldComponentUpdate: (props, state) ->
    @props.active isnt props.active or
    @props.folder.name isnt props.folder.name or
    @props.folder.count isnt props.folder.count
  onClick: ->
    if @global.state.folder?.type isnt @props.folder.type or @global.state.tag?
      tag = null
      folder = null
      if @props.folder?.type isnt 6
          folder = Store.collections.folders.filtered('type == $0', @props.folder.type)[0] or null
      else
          folder = { type: 6 }
      if folder?
        Object.assign(@global.state, { tag, folder })
  render: ->
    <li onClick={@onClick} className={if @props.active then 'active' else ''}>
      <div>{@props.folder.name}</div>
      <div>{if @props.folder.count > 0 then @props.folder.count.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",") else ''}</div>
    </li>

ActiveBar = React.createClass
  displayName: 'ActiveBar'
  global: Store.global
  shouldComponentUpdate: (props, state) ->
    props.type isnt @props.type or
    props.tag isnt @props.tag
  render: ->
    tags = ['social', 'personal', 'service', 'newsletter']
    folderType = @props.type
    hide = false
    if not folderType?
      hide = true
    if folderType is 4
      folderType += 1
    else if folderType is 6
      folderType = 4
    <div className="selected #{tags[@props.tag]}" style={transform:"translate3d(#{if hide then -3.5 else 0}px, #{(folderType)*31}px, 0)"}></div>

Navigation = React.createClass
  displayName: "Navigation"
  global: Store.global
  accounts: Store.collections.accounts
  folders: Store.collections.folders.filtered('type == 5 || type == 7')
  countFilters: [
    Store.collections.conversations
         .filtered('messages.folder.type == 1 && messages.folder.type != 4 && unread == true')
    Store.collections.conversations
         .filtered('messages.folder.type == 3')
  ]
  defaultFolders: ->
    [
      {
        name: 'Inbox'
        type: 1
        count: @countFilters[0].length
      }
      {
        name: 'Sent'
        type: 2
      }
      {
        name: 'Drafts'
        type: 3
        count: @countFilters[1].length
      }
      {
        name: 'Downloads'
        type: 6
        count: Store.collections.files.length
      }
      {
        name: 'Trash'
        type: 4
      }
    ]
  componentDidMount: ->
    Store.collections.addListeners ['folders', 'accounts', 'conversations', 'files'], @force
    @global.addListener(@force)
  componentWillUnmount: ->
    for type in ['folders', 'accounts', 'conversations', 'files']
      Store.collections.removeListener(type, @force)
    @global.removeListener(@force)
  force: ->
    window.requestAnimationFrame( =>
      @forceUpdate()
    )
  compose: ->
    composer = new BrowserWindow({ width: 751, height: 552, frame: false, backgroundColor:'#FFF' })
    composer.loadURL("file://#{app.getAppPath()}/static/index-hot-load.html?compose")
  render: ->
    <div className="navigation">
      <div className="toolbar-partial">
        {
          if process.platform is 'darwin'
            <div className="window-controls mac">
              <div onClick={=> BrowserWindow.getFocusedWindow().close()}><img src="../static/images/close.svg"></img></div>
              <div onClick={=> BrowserWindow.getFocusedWindow().minimize()}><img src="../static/images/minimize.svg"></img></div>
              <div onClick={=> BrowserWindow.getFocusedWindow().setFullScreen(not BrowserWindow.getFocusedWindow().isFullScreen())}><img src="../static/images/fullscreen.svg"></img></div>
            </div>
        }
        <paper-icon-button onClick={@compose} src="./images/compose.svg"></paper-icon-button>
      </div>
      <ul>
        {
          @defaultFolders().map((folder, idx) =>
            <NavItem folder={folder} active={folder?.type is @global.state.folder?.type} key={idx} />
          )
        }
      </ul>
      <div className="spacer"></div>
      <ul>
        <li>tags</li>
        {
          [['social', 'Social'], ['personal', 'Personal'], ['service', 'Services'], ['newsletter', 'Newsletters']]
          .map(([tag, name], index) =>
            <li key={tag}>
              <div className={tag}></div>
              <div onClick={=> @global.state.tag = index}>{name}</div>
            </li>
          )
        }
      </ul>
      <div className="seperator"></div>
      <ul>
      {
        folders = Lazy(@folders).filter((folder) ->
          folder.isValid()
        )
        .uniq("path")
        .sortBy (folder) ->
          folder.name
        .groupBy (folder) ->
          ###
          path = if folder.path.indexOf("/") > -1 then folder.path.split("/")[0] else folder.path
          if /^\[(.*)\]/i.test(path)
            path = path.match(/^\[(.*)\]/i)[1]
          path
          ###
          folder.parent ? folder.name
        .toArray()
        for folder in folders
          <FolderParent folder={folder} key={folder.path}></FolderParent>
      }
      </ul>
      <ActiveBar type={@global.state.folder?.type} tag={@global.state.tag}></ActiveBar>
      <div className="accounts">
      {
        for account in @accounts
          continue unless account.isValid()
          <div className="account active" key={ account.address }>
            <div className="avatars">
              <div className="avatar"></div>
            </div>
            <div className="info">
              <div className="name">{ account.name ? account.address }</div>
              <div className="description">Gmail</div>
            </div>
          </div>
      }
      </div>
    </div>

module.exports = Navigation
