require 'shelljs/global'
_ = require 'prelude-ls'
require! \verify
pad = require! \zpad

# constants
HOUR = 60 * 60 * 1000
MINUTE = 60 * 1000
SECOND = 1000
PARSER = /trim\((\d+),(\d+)\)/gi

time-format = (ms) ->
  hh = 0; mm = 0; ss = 0
  hh = ~~  (ms / HOUR)
  mm = ~~ ((ms - hh * HOUR) / MINUTE)
  ss = ~~ ((ms - hh * HOUR - mm * MINUTE) / SECOND)
  ms = ~~  (ms - hh * HOUR - mm * MINUTE - ss * SECOND + 0.5)
 
  "#{pad hh}:#{pad mm}:#{pad ss}.#{pad ms, 3}"

parse-keyframes = (input) ->

  # supports XviD and x264 stats files
  regex =
    xvid: /^([ipb])/i
    x264: /type:([ipb])/i

  lines = input |> _.lines
  mode = switch
  | /^# XviD/   == lines.0 => (lines .= slice 2) and \xvid
  | /^#options/ == lines.0 => (lines .= slice 1) and \x264

  i = 0; len = lines.length - 1; res = []
  while i < len
    if test = lines[i++].match regex[mode]
      res.push test.1.to-upper-case!

  res

# default options
defaults =
  input-fps: 30000/1001
  output-fps: 24000/1001
  keyframes: void # string of file contents, not a path
  timecodes: void # string of file contents, not a path
  lookaround: 3
  template: void # if no template is specified, automatic guessing will be used
  format: \mkv # formats: mkv/ogm/json
  verify: true # browser-based verification

# input should be a string, not a file path
autochapter = (input, options, callback) ->

  # load options
  opts = defaults with options
  opts.input = input

  # find the first line with a trim on it
  trim-line = input
  |> _.lines
  |> _.find (.match PARSER)

  # generate initial trims
  trims = []; i = 0
  while trim = PARSER.exec trim-line
    trims.push {start: (parse-int trim[1], 10), end: (parse-int trim[2], 10)}
    t = trims[i]
    t.input-frames = t.end - t.start + 1
    t.input-length = t.input-frames * (1000ms / opts.input-fps)
    if opts.output-fps is not opts.input-fps
      t.output-frames = Math.round t.input-length / (1000ms / opts.output-fps)
    else
      t.output-frames = t.input-frames
    t.start-frame = 0
    index = i++
    while index > 0
      t.start-frame += trims[--index].output-frames
    t.end-frame = t.start-frame + t.output-frames - 1

  # do keyframe snapping if keyframes specified
  if opts.keyframes
    kfs = parse-keyframes that
    distance = [0] ++ _.flatten [[x, -x] for x from 1 to opts.lookaround]
    # generates an array like [0, 1, -1, 2, -2, 3, -3]

    for t,i in trims
      offset = (_.find (-> kfs[t.start-frame + it] is \I), distance) or 0
      t.start-frame += offset
      t.output-frames += offset
      pt = trims[i-1] if i > 0
      if pt then
        pt.end-frame += offset
        pt.output-frames += offset
  
  # run the verification process
  trims <-! verify trims, opts

  # calculate actual chapter times
  for t,i in trims
    t.start-time = time-format t.start-frame * (1000ms / opts.output-fps)
    t.end-time = time-format t.end-frame * (1000ms / opts.output-fps)
    t.length-time = time-format t.output-frames * (1000ms / opts.output-fps)

# helper function with file IO (sync)
make-chapters = (infile, opts, outfile) ->
  input = cat infile
  opts.keyframes ?= cat opts.keyframes
  opts.timecodes ?= cat opts.timecodes
  opts.template  ?= cat opts.template
  output <-! autochapter input, opts
  output.to outfile