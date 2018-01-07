React = require 'react'
ReactDOM = require 'react-dom'
dynamics = require 'dynamics.js'
rubberBandDistance = (offset, dimension) ->
  constant = 0.55
  scalingFactor = 0.2
  result = (constant * Math.abs(offset) * dimension) / (dimension + constant * Math.abs(offset))
  return scalingFactor*(if offset < 0.0 then -result else result)
# TODO when scrolling set style={ pointerEvents: 'none'} on children
RubberBand = React.createClass
  displayName: 'RubberBand'
  componentDidMount: ->
    @scrollTouchDown = false
    window.addEventListener 'scroll-touch-begin', @onScrollTouchDown
    window.addEventListener 'scroll-touch-end', @onScrollTouch
    that = @
    @x = 0
    @locked = false
    @debounceTimeout = null
    #momentum = false
    ReactDOM.findDOMNode(@refs.container).addEventListener('wheel', @onWheel)
  componentWillUnmount: ->
    window.removeEventListener 'scroll-touch-begin', @onScrollTouchDown
    window.removeEventListener 'scroll-touch-end', @onScrollTouch
    ReactDOM.findDOMNode(@refs.container).removeEventListener('wheel', @onWheel)
  onWheel: (e) ->
    container = ReactDOM.findDOMNode(@refs.container)
    # TODO bring proper momentum back?
    maxScroll = container.scrollHeight - container.clientHeight
    # TODO properly determine direction with e.wheelDelta
    if container.scrollTop is 0
      scrollTop = (parseFloat(container.style.paddingTop.slice(0,-2)) or 0)
      newBoundsOriginY = scrollTop - @x
      minBoundsOriginY = 0.0
      maxBoundsOriginY = window.innerHeight - 50 # wrong?
      constrainedBoundsOriginY = Math.max(minBoundsOriginY, Math.min(newBoundsOriginY, maxBoundsOriginY))
      rubberBandedY = rubberBandDistance(newBoundsOriginY - constrainedBoundsOriginY, window.innerHeight - 50)
      container.style.paddingTop = Math.abs(constrainedBoundsOriginY + rubberBandedY) + 'px'
      velocity = Math.max(7, Math.abs(e.wheelDelta))
      #momentum = true if not that.scrollTouchDown and velocity > 600
      if @scrollTouchDown
        #or (momentum and velocity > 250)
        clearTimeout(@debounceTimeout)
        if e.wheelDelta < 0
          @x -= velocity
          @x = 0 if @x < 0
        else
        	@x += velocity
        @debounceTimeout = setTimeout =>
          #momentum = false
          if not @scrollTouchDown
            paddingTop = (parseFloat(container.style.paddingTop.slice(0,-2)) or 0)
            if paddingTop > 0
              window.requestAnimationFrame( =>
                dynamics.animate(container, {
                  paddingTop: 0
                }, { type: dynamics.spring, frequency: 1, duration: 500, complete: =>
                  @x = 0
                })
              )
        , 100
    else if maxScroll is container.scrollTop
      scrollTop = (parseFloat(container.style.marginBottom.slice(0,-2)) or 0)
      newBoundsOriginY = scrollTop - @x
      minBoundsOriginY = 0.0
      maxBoundsOriginY = window.innerHeight - 50 # wrong?
      constrainedBoundsOriginY = Math.max(minBoundsOriginY, Math.min(newBoundsOriginY, maxBoundsOriginY))
      rubberBandedY = rubberBandDistance(newBoundsOriginY - constrainedBoundsOriginY, window.innerHeight - 50)
      container.style.marginBottom = Math.abs(constrainedBoundsOriginY + rubberBandedY) + 'px'
      velocity = Math.max(7, Math.abs(e.wheelDelta))
      #momentum = true if not that.scrollTouchDown and velocity > 600
      if @scrollTouchDown
        #or (momentum and velocity > 250)
        clearTimeout(@debounceTimeout)
        if e.wheelDelta > 0
          @x -= velocity
          @x = 0 if @x < 0
        else
        	@x += velocity
        @debounceTimeout = setTimeout =>
          #momentum = false
          if not @scrollTouchDown
            paddingTop = (parseFloat(container.style.marginBottom.slice(0,-2)) or 0)
            if paddingTop > 0
              window.requestAnimationFrame( =>
                dynamics.animate(container, {
                  marginBottom: 0
                }, { type: dynamics.spring, frequency: 1, duration: 500, complete: =>
                  @x = 0
                })
              )
        , 100
  onScrollTouch: ->
    @scrollTouchDown = false
  onScrollTouchDown: ->
    @scrollTouchDown = true
  render: ->
    <div className={@props.class} ref="container" style={@props.style} onScroll={@props.onScroll}>
      {@props.children}
    </div>

module.exports = RubberBand
