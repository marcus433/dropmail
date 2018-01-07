class TimeNotation
  timer: null
  constructor: (@timestamp, type = 'short') ->
    date = new Date(@timestamp)
    @diff = Math.abs(new Date().getTime() - @timestamp)
    s = ['th','st','nd','rd']
    d = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']
    m = ['January','February','March','April','May','June','July','August','September','October','November','December']
    @day = date.getDate()
    v = @day % 100
    ordinal = s[(v - 20)%10] or s[v] or s[0]
    @dayn = d[date.getDay()]
    @day = "#{@day}#{ordinal}"
    @year = date.getFullYear() / 1
    @month = date.getMonth()
    @month = m[@month].slice(0, 3)
    @hour = date.getHours()
    @mode = 'AM'
    if @hour >= 12
      @hour -= 12
      @mode = 'PM'
    if @hour is 0
      @hour = 12
    @minute = date.getMinutes()
    @minute = "0#{@minute}" if @minute < 10
  replyFormat: =>
    "#{@month} #{@day}, #{@year} at #{@hour}:#{@minute} #{@mode}"
  format: =>
    if @diff < 60*1000
      'Just Now'
    else if @diff < 60 * 10 * 1000
      ago = Math.floor(@diff/(60 * 1000))
      "#{ago} minute#{if ago > 1 then 's' else ''} ago"
    else if @diff < 60 * 60 * 24 * 1000
      "#{@hour}:#{@minute} #{@mode}"
    else if @diff < 60 * 60 * 24 * 7 * 1000 # TODO get rid of this?
      ago = Math.floor(@diff/(60 * 60 * 24 * 1000))
      if ago is 1 then "Yesterday" else "#{@dayn}"
    else if @diff < 60 * 60 * 24 * 7 * 4 * 12 * 1000
      "#{@month} #{@day}"
    else
      "#{@month} #{@day} #{@year}" # TODO switch to /// format?
  state: =>
    # TODO
    @format()
  unmount: =>
    clearTimeout(@timer)
    @hour = @mode = @minute = @diff = @month = @day = @timestamp = @year = null

module.exports = TimeNotation
