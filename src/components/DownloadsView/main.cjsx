require './_main.scss'
React = require 'react'
ReactDOM = require 'react-dom'
RubberBand = require '../Rubberband/Main'
Store = require '../../store'
{ remote: { app } } = require 'electron'
FILES_PATH = app.getPath('userData')+'/files/'

Files = Store.collections.files.sorted('filename', true).snapshot() # TODO: timestamp
itemHeight = 250 + (25 * 2)
itemWidth = 200 + (25 * 2)

DownloadsItem = React.createClass
  displayName: "DownloadsItem"
  getInitialState: ->
    cascade: true
    huge: false
    hover: false
    inactive: false
    down: false
  componentDidMount: ->
    Store.actions.addListener('file-hover', @onHover)
    Store.actions.addListener('file-leave', @onLeave)
  componentWillUnmount: ->
    Store.actions.removeListener('file-hover', @onHover)
    Store.actions.removeListener('file-leave', @onLeave)
  onClick: ->
  onHover: (id) ->
    if not @state.hover and Files[@props.index].id is id
      @setState(hover: true, inactive: false)
    else if not @state.inactive
      @setState(inactive: true, hover: false)
  onLeave: ->
    @setState(hover: false, inactive: false, down: false)
  onDown: ->
    @setState(down: true)
  onUp: ->
    @setState(down: false)
  hover: ->
    Store.actions.dispatch('file-hover', [Files[@props.index].id])
  leave: ->
    Store.actions.dispatch('file-leave', [])
  preview: ->
    file = Files[@props.index]
    # TODO: size threshold could vary
    if file.saved and file.size <= 2000000 and file.mimeType[0...5] is 'image'
      return "#{FILES_PATH}#{file.id}"
    false
  mimetype: ->
    ###
    file = Files[@props.index]
    if file.mimeType[0...5] is 'image'
    else if file.mimeType[0...5] is 'image' # audio
    else if file.mimeType[0...5] is 'image' # pdf
    else if
    ###
  onDrag: (e) ->
    file = Files[@props.index]
    if file.saved
      # TODO: will stream file from server
      e.dataTransfer.setData('DownloadURL', "#{FILES_PATH}#{file.id}")
  render: ->
    <div
      className="download#{if @state.huge then ' huge' else ''}#{if @state.inactive then ' inactive' else ''}"
      onMouseOver={@hover}
      onMouseOut={@leave}
      onMouseDown={@onDown}
      onMouseUp={@onUp}
      onClick={@onClick}
      draggable={Files[@props.index].saved}
      onDragStart={@onDrag}
      style={transform: "translate3d(#{@props.column * itemWidth}px, #{@props.row * itemHeight}px, 0) #{if @state.hover then 'scale(1.1,1.1)' else ''} #{if @state.down then 'scale(0.9)' else ''}"
      }>
      <div className="preview">
        {
          preview = @preview()
          if preview
            <img src={preview} draggable="false"/>
          else
            <iron-icon icon={if @props.index % 2 then "av:movie" else if @props.index % 3 then "hardware:headset" else "image:photo"}></iron-icon>
        }
      </div>
      <div className="details">
        <div className="title">{Files[@props.index]?.filename}</div>
        <iron-icon icon="icons:file-download"></iron-icon>
      </div>
    </div>

DownloadsView = React.createClass
  displayName: "DownloadsView"
  getInitialState: ->
    hidden: true
    scrolling: true
    viewport: {
      visible: 0
      first: 0
      last: 0
    }
    width: 0
    loading: true
  global: Store.global
  componentDidMount: ->
    @setState(scrolling: false)
    @global.addListener =>
      if @global.state.folder?.type is 6
        @setState(hidden: false) if @state.hidden
        # THis is hacky... shouldn't do 1s
        setTimeout =>
          @scroll(true)
          setTimeout =>
            @setState(loading: false)
          , 400
        , 1000
      else if not @state.hidden
        @setState(hidden: true)
    Store.collections.addListener 'files', =>
      @forceUpdate()
    ###
        width: 200px;
        height: 250px;
        margin: 25px;

        outer padding: 30px;
    ###
  scroll: (force) ->
    if force isnt true
      @setState(scrolling: true) if not @state.scrolling
      clearTimeout(@scrolltimeout)
      @scrolltimeout = setTimeout =>
        @setState(scrolling:false)
      , 150
    viewport = {}
    viewport.visible = Math.ceil(window.innerHeight / itemHeight) # TODO: 30 * 2?
    viewport.first = Math.floor(ReactDOM.findDOMNode(@refs.container).scrollTop / itemHeight)
    viewport.last = Math.min(viewport.first + viewport.visible, Files.length)
    return if viewport.first is @state.viewport.first and viewport.last is @state.viewport.last and force isnt true
    @setState({ viewport, width: ReactDOM.findDOMNode(@refs.container).getBoundingClientRect().width })
  render: ->
    itemHeight = 250 + (25 * 2)
    columns = Math.floor((@state.width - (30 * 2)) / (200 + (25 * 2)))
    <RubberBand class="downloads-view #{if @state.loading then 'loading' else ''} #{if not @state.scrolling then 'scrolling' else ''}" style={display: if @state.hidden then "none"} onScroll={@scroll} ref="container">
      <div className="downloads-container" style={height: Math.ceil((Files.length / columns)) * itemHeight, width: @state.width - 60, pointerEvents: (if @state.scrolling then 'none' else 'auto')}>
        {
          for File, i in Files.snapshot()[(@state.viewport.first * columns) ... Math.min(((@state.viewport.last * columns)+(2 * columns)), Files.length)]
            continue unless File.isValid()
            index = (@state.viewport.first * columns)+i
            <DownloadsItem index={index} column={Math.ceil(index % columns)} row={Math.ceil((index + 1) / columns) - 1} key={File.id}></DownloadsItem>
        }
      </div>
    </RubberBand>

module.exports = DownloadsView
