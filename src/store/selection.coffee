Promise = require 'bluebird'
# TODO, extends get(idx) to whenever the selection is 1.
# TODO walking animation so the selectable items are always in view.
class Selection
	ranges: []
	lastSelected: 0
	listeners: []
	constructor: (@global, @collections) ->
		@meta = false
		document.onkeydown = (e) =>
			prop = ->
				if e.stopPropagation
					e.stopPropagation()
					e.preventDefault()
			code = if e.keyCode then e.keyCode else e.which
			if (e.ctrlKey and process.platform isnt 'darwin') or e.metaKey
				@meta = true
				keyCode = String.fromCharCode(code).toLowerCase()
				if 'a' is keyCode
					prop()
					@selectAll(@collections.focus?.length or 0)
			else if code is 40
				prop()
				if @shift
					@walkMultiselect(-1)
				else
					@walkOne(-1)
			else if code is 38
				prop()
				if @shift
					@walkMultiselect(1)
				else
					@walkOne(1)
			else if e.shiftKey
				@shift = true
		document.onkeyup = (e) =>
			if not e.shiftKey
				@shift = false
			if (not e.ctrlKey and process.platform isnt 'darwin') or not e.metaKey
				@meta = false
		@reset()
	addListener: (callback) =>
		@listeners.push(callback)
	removeListener: (callback) =>
    idx = @listeners.indexOf(callback)
    @listeners.splice(idx, 1) if idx > -1
	dispatch: =>
		window.requestAnimationFrame( =>
	    next = (idx) =>
	      return if idx < 0
	      @listeners[idx]()
	      next(--idx)
	    next(@listeners.length - 1)
		)
	reset: =>
		# TODO: what if the range doesn't exist in the subset?
		@collections.focus.addListener(@recalculate)
		if @collections.focus.length > 0
			@ranges = [[0, 0]]
		else
			@ranges = []
		@lastSelected = 0
	recalculate: (collection, changes) =>
		console.log 'reclaculating'
		# TODO: not updating properly after delete
		# TODO: update lastSelected & focus
		# TODO: for some reason when there is a subselection of range length 1 and it is deleted there is a crash
		# TODO: run TimSort, necessary because non-reverse results in idx < start failing
		for idx in changes.deletions by -1
			@lastSelected-- if idx < @lastSelected
			offset = 0
			for i in [0...@ranges.length]
				[start, end] = @ranges[i - offset]
				if start is end and idx is start
					@ranges.splice(i - offset, 1)
					offset++
				else if idx < start
					@ranges[i - offset] = [start - 1, end - 1]
					if @ranges[i - offset - 1]? and @ranges[i - offset]?
						if @ranges[i - offset - 1][1] + 1 >= @ranges[i - offset][0]
							@ranges[i - offset - 1] = [@ranges[i - offset - 1][0], @ranges[i - offset][1]]
							@ranges.splice(i - offset, 1)
							offset++
				else if idx is start or idx <= end
					@ranges[i - offset] = [start, end - 1]
		for idx in changes.insertions
			@lastSelected++ if idx <= @lastSelected
			offset = 0
			for i in [0...@ranges.length]
				[start, end] = @ranges[i + offset]
				if idx <= start
					@ranges[i + offset] = [start + 1, end + 1]
				else if idx <= end
					@ranges[i + offset] = [start, idx - 1]
					@ranges.splice(i + offset + 1, 0, [idx + 1, end + 1])
					offset++
		@lastSelected = 0 if @lastSelected < 0
		@dispatch()
		return
	isSelected: (idx) ->
		# TODO build in binary search
		return true for [s, e] in @ranges when e >= idx >= s
		false
	select: (idx) ->
		throw 'Please select fewer ranges.' if @ranges.length is 30
		@lastSelected = idx
		for [start, end], i in @ranges
			#return if idx is start or end >= idx >= start
			if idx+1 is start
				return @ranges[i][0] = idx
			else if idx-1 is end
				if @ranges[i+1]? and (@ranges[i+1][0] is idx or @ranges[i+1][0] is idx+1)
					idx = @ranges[i+1][1]
					@ranges.splice(i+1, 1)
				return @ranges[i][1] = idx
			else if start > idx
				return @ranges.splice(i, 0, [idx, idx])
		@ranges.push([idx, idx])
		return
	multiselect: (idx) ->
		min = Math.min.apply(null, [@lastSelected, idx])
		max = Math.max.apply(null, [@lastSelected, idx])
		range = [min, max]
		indices = []
		for [start, end], idx in @ranges
			if range[0] >= start and range[1] is end
				return
			else if start <= range[0] <= end
				range[0] = start if start >= min
				indices.push(idx)
			else if start <= range[1] <= end
				range[1] = end if end <= @lastSelected
				indices.push(idx)
			else if end + 1 is range[0]
				range[0] = start if start >= min
				indices.push(idx)
			else if start - 1 is range[1]
				range[1] = end if end <= @lastSelected
				indices.push(idx)
			else if range[0] < start and range[1] > end
				indices.push(idx)
		changed = 0
		[others..., last] = indices
		for idx, i in others
			changed += @ranges.splice(idx - changed, 1).length
		@ranges.splice(last - changed, 1, range)
		@dispatch()
		return
	deselect: (idx) ->
		# NOTE: Condense logic, can combine isSelected & for loop funcs.
		@lastSelected = idx + (if @isSelected(idx+1) then +1 else -1)
		@lastSelected = if idx < 0 then 0 else idx
		for [start, end], i in @ranges
			if end >= idx >= start
				if start is end
					return @ranges.splice(i, 1)
				else if start is idx
					return @ranges[i][0]++
				else if end is idx
					return @ranges[i][1]--
				else
					if @ranges[i+1]?
						@ranges.splice(i+1, 0, [idx + 1, @ranges[i][1]])
					else
						@ranges.push([idx + 1, @ranges[i][1]])
					return @ranges[i][1] = idx - 1
	walkOne: (direction) ->
		perspective = [@lastSelected, @lastSelected]
		for [min, max] in @ranges
			if min <= @lastSelected <= max
				perspective = [min, max]
				break
		if direction is 1
			min = perspective[0]
			idx = min - 1
			idx = 0 if min <= 0
			@lastSelected = idx
			@ranges = [[idx, idx]]
		else if direction is -1
			max = perspective[1]
			idx = max + 1
			# TODO need to add a internal check to say if idx > internal_count then idx = max.
			@lastSelected = idx
			@ranges = [[idx, idx]]
		@global.state.conversation = @collections.focus?[@lastSelected]
		@dispatch()
		return
	walkMultiselect: (direction) ->
		# TODO: need boundaries
		@select(@lastSelected - direction)
		# TODO: IDK the meachanics of this yet... this is temporary
		@dispatch()
		return
	toggleSelect: (idx) ->
		if @isSelected(idx)
			@deselect(idx)
		else
			@select(idx)
		@dispatch()
		return
	selectOne: (idx) ->
		@lastSelected = idx
		@ranges = [[idx, idx]]
		@global.state.conversation = @collections.focus?[idx]
		@dispatch()
		return
	selectAll: (count) ->
		@lastSelected = 0
		@ranges = [[0, count]]
		@dispatch()
		return
	count: ->
		count = 0
		count += (max-min)+1 for [min, max] in @ranges
		count

module.exports = Selection
