ASYNC  = require 'async'
FS     = require 'fs'
PATH   = require 'path'
mkdirp = require 'mkdirp'
EventEmitter = require('events').EventEmitter


_merge = (base, config) ->
  base[key] = value for key, value of config

class AppManifest extends EventEmitter

  ##############
  # DEFAULT PROPERTIES
  #

  categories: ['master', 'network', 'fallback']
  fallback:   []
  network:    ['*']

  ##############
  # PUBLIC METHODS
  #

  constructor: () ->
    _merge(@, config) for config in arguments
    @invalidate = @invalidate.bind @
    @pipeline.on 'invalidate', @invalidate

    # TODO: rethink these rules a bit. maybe just throw exception if you don't
    # pass a RegExp or array of RegExps?
    @include ||= []
    @include = if @include instanceof Array then @include else [@include]

  # Detects that the given path is handled by this packager.
  exists: (path, done) ->
    done path == @path

  # Returns all paths generated by this packager
  findPaths: (done) ->
    done = @_error done
    done null, [@path]

  # Returns an asset descriptor for the named path. Only works if this path
  # is supported by the packager.
  build: (srcPath, done) ->
    done = @_error done
    return if @_checkPath srcPath, done
    if !@_build
      @_build = ASYNC.memoize (done) =>

        ASYNC.waterfall [
          ((next) =>
            @pipeline.findPaths (err, paths) =>
              return next(err) if err
              urlRoot = @pipeline.urlRoot or '/'
              paths = paths.filter (path) => 
                (path != @path) and
                @include.some (regex) -> regex.exec path

              # make sure all assets get built to activate watchers.
              paths.forEach((path) => @pipeline.build path) if @watch 
              paths = paths.map (path) => PATH.join urlRoot, path
              next err, paths
          ),

          ((master, next) =>
            entries = @categories.map (category) =>
              if category == 'master'
                lines = master
                category = 'cache'
              else
                lines = @[category]

              """
              #{category.toUpperCase()}:
              #{lines.join("\n")}
              
              """
            next null, entries
          ),

          ((entries, next) =>
            @emit 'info', "built #{@path}"
            next null,            
              path: @path
              type: 'text/cache-manifest'
              body: """
                    CACHE MANIFEST
                    # generated on #{Date.now()}

                    #{entries.join("\n")}
                    """
          )

        ], done


    @_build done


  # Invalidate any caches in this packagers so that the next build will
  # regenerate.
  invalidate: () ->
    @emit 'invalidate' if @_build
    @_build = null # reset 

  ##############
  # PRIVATE METHODS
  #

  _checkPath: (srcPath, done) ->
    invalid = srcPath != @path
    done(new Error("#{srcPath} not found")) if invalid
    invalid

  _error: (done) ->
    self = @
    (err) ->
      self.emit 'error', err if err
      done.apply self, arguments if done
    

module.exports = AppManifest