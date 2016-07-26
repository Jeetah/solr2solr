path = require 'path'
solr = require 'solr'
_ =    require 'underscore'

class SolrToSolr

  go: (@config) ->
    @sourceClient = solr.createClient(@config.from)
    @destClient   = solr.createClient(@config.to)
    @clearDestination(@config.clearDestination)
    @nextBatch(@config.start)
    
  clearDestination: (clear) ->
    console.log "Clearing destination? #{clear}"
    if clear
      console.log "Destination will be cleared"
      @destClient.del null,@config.clearQuery, (err, response) =>
        return console.log "Some kind of solr query error #{err} during deleteion" if err?
        @destClient.commit()

  nextBatch: (start) ->
    console.log "Querying starting at #{start}"
    @sourceClient.query @config.query, {rows:@config.rows, start:start}, (err, response) =>
      return console.log "Some kind of solr query error #{err}" if err?
      responseObj = JSON.parse response

      newDocs = @prepareDocuments(responseObj.response.docs, start)
      @writeDocuments newDocs, =>
        start += @config.rows
        if responseObj.response.numFound > start
          @nextBatch(start)
        else
          @destClient.commit()

  prepareDocuments: (docs, start) =>
    for doc in docs
      newDoc = {} 
      if @config.clone
        for cloneField of doc
          newDoc[cloneField] = doc[cloneField]
      else
        for copyField in @config.copy
          newDoc[copyField] = doc[copyField] if doc[copyField]?
      for transform in @config.transform
        newDoc[transform.destination] = doc[transform.source] if doc[transform.source]?
      for fab in @config.fabricate
        vals = fab.fabricate(newDoc, start)
        newDoc[fab.name] = vals if vals?
      start++
      newDoc

  writeDocuments: (documents, done) ->
    docs = []
    docs.push documents
    if @config.duplicate.enabled
      for doc in documents
        for num in [0..@config.duplicate.numberOfTimes]
          newDoc = _.extend({}, doc)
          newDoc[@config.duplicate.idField] = "#{doc[@config.duplicate.idField]}-#{num}"
          docs.push newDoc

    @destClient.add _.flatten(docs), (err) =>
      console.log err if err
      @destClient.commit()
      done()

exports.go = (config) ->
  (new SolrToSolr()).go(config)
