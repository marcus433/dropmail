class QuoteParser
  content: null
  constructor: (type, @content) ->
    ###
    INPUT: message body
    OUTPUT:
      [
        { type: 'html', content: '' },
        { type: 'text', content: '' },
        { type: 'signature', content: ''},
        { type: 'quoted', content: '' },
        { type: 'forward', content: '' }
      ]
    ###
