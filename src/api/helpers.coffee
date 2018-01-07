Promise = require 'bluebird'
realm = require './realm'

class Helpers
  inTransaction: false
  queue: []
  sleep: (ms) ->
    new Promise (resolve) ->
      setTimeout(->
        resolve()
      , ms)
  transaction_next: =>
    return if @queue.length is 0
    callback = @queue[0]
    try
      realm.write( =>
        callback(tx: true)
      )
    finally
      @queue.splice(0, 1)
      if @queue.length > 0
        @transaction_next()
      else
        @inTransaction = false
  transaction: (trace, callback) =>
    if trace? and trace.tx is true
      return callback(trace)
    @queue.push(callback)
    if not @inTransaction
      @inTransaction = true
      @transaction_next()
  whereIn: (needle, haystack) =>
    values = []
    for hay in haystack
      values.push("#{needle} == $#{values.length}")
    values.join(' || ')
  whereNotIn: (needle, haystack) =>
    values = []
    for hay in haystack
      values.push("#{needle} != $#{values.length}")
    values.join(' && ')

module.exports = new Helpers()
