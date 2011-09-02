#!/usr/bin/env ruby
#


###
#
# File: Vocabulary.rb
#
######


###
#
# (c) 2011, Copyright, Bjoern Rennhak
#
# @file       Vocabulary.rb
# @author     Bjoern Rennhak
#
#######


# Libraries {{{

# OptionParser related
require 'optparse'
require 'optparse/time'
require 'ostruct'
require 'pp'
require 'date'

# Standard includes
require 'rubygems'

# Custom includes (changes object behaviors)
load 'Extensions.rb'
load 'Logger.rb'

# }}}


# The Vocabulary class takes care of creating simple flash cards in LaTeX
class Vocabulary # {{{

  # Constructor of the JokeMachine class
  #
  # @param [OpenStruct] options   Requires an OpenStruct object with the result of the ARGV processing (Vocabulary::parse_cmd_arguments)
  def initialize options = nil # {{{
    @options = options

    @log     = Logger.new( @options )

    # Minimal configuration
    @config                       = OpenStruct.new
    @config.os                    = "Unknown"
    @config.platform              = "Unknown"
    @config.encoding              = "UTF-8"
    @config.archive_dir           = "archive"
    @config.config_dir            = "configurations"
    @config.cache_dir             = "cache"

    unless( options.nil? )
      @log.message :success, "Starting #{__FILE__} run"
      @log.message :debug,   "Colorizing output as requested" if( @options.colorize )

      ####
      # Main Control Flow
      ##########

      # Input flash cards
      if( @options.manual_input )
        while( true )
          manual_input
          answer = get_choice_from_bipolar( "More input?" )
          break unless( answer )
        end
      end # of if( @options.manual_input )

    end # of unless( options.nil? )
  end # of def initalize }}}


  # The function handles when a user wants to input a flash card directly via the CLI
  #
  # @returns  [Card]    Returns a card object
  def manual_input # {{{

    # Convenience shorthand 
    yellow = Proc.new { |m| @log.colorize( "Yellow", m.to_s ) }

    STDOUT.flush
    #$/ = '\r\n'

    puts yellow.call( ">> Flash card side 1: " )
    title = STDIN.readline.chomp

    # Aquire data
    puts yellow.call( "\n>> Please type your [[ FLASH CARD SIDE ]] here and after you are finished hit CTRL+D twice\n" )

    # The method over the re-def over $/ = "END" works too, but mangles later STDIN.gets somehow - why?
    content = ""
    while true
      begin
        input = STDIN.sysread(1)
        content += input
      rescue EOFError
        break
      end
    end

    answer        = get_choice_from_bipolar( "Do you want to use this flashcard? "  )

    if( answer ) 
      res = new.save!
      answer = ( res ) ? ( "Success !" ) : ( "Failure !" )
      puts yellow.call( answer )
    end

    # FIXME
    [title, content]
  end # of def manual_input }}}


  # The function ask will take a simple string query it on the CMD and wait for an answer e.g. "y" (or enter)
  #
  # @param   [String]   question          String, representing the question you want to query.
  # @param   [Array]    allowed_answers   Array, representing the allowed answers
  # @returns [Boolean]                    Boolean, true for yes, false for no
  def get_choice_from_bipolar question, allowed_answers = %w[ y n ENTER ] # {{{
    print "#{question.to_s} [#{allowed_answers.join(", ")}] : "
    STDOUT.flush
    answer = STDIN.gets.to_s
    if( answer =~ %r{^\n$}i )
      answer = "enter"
    else
      answer = answer.chomp.downcase
    end

    return true  if( answer =~ %r{y|enter}i )
    return false if( answer =~ %r{n}i )
  end # of def ask }}}


  # The function 'parse_cmd_arguments' takes a number of arbitrary commandline arguments and parses them into a proper data structure via optparse
  #
  # @param    [Array]         args  Ruby's STDIN.ARGS from commandline
  # @returns  [OpenStruct]          OpenStruct object containing the result of the parsing process
  def parse_cmd_arguments( args ) # {{{

    original_args                           = args.dup
    options                                 = OpenStruct.new

    # Define default options
    options.colorize                        = false
    options.debug                           = false
    options.manual_input                    = false

    pristine_options                        = options.dup

    opts                                    = OptionParser.new do |opts|
      opts.banner                           = "Usage: #{__FILE__.to_s} [options]"

      opts.separator ""
      opts.separator "General options:"

      opts.on("-m", "--manual-input", "Input a joke manually to the Database") do |m|
        options.manual_input = m
      end

      opts.separator ""
      opts.separator "Specific options:"

      opts.on("-d", "--debug", "Run in debug mode") do |d|
        options.debug = d
      end

      opts.separator ""
      opts.separator "Common options:"

      # Boolean switch.
      opts.on("-c", "--colorize", "Colorizes the output of the script for easier reading") do |c|
        options.colorize = c
      end

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      # Another typical switch to print the version.
      opts.on_tail("--version", "Show version") do
        puts `git describe --tags`
        exit
      end
    end

    opts.parse!(args)

    # Show opts if we have no cmd arguments
    if( original_args.empty? )
      puts opts
      exit
    end

    options
  end # of parse_cmd_arguments }}}


  # Reads a YAML config describing the joke source to aquire from
  #
  # @param    [String]      filename    String, representing the filename and path to the config file
  # @returns  [OpenStruct]              Returns an openstruct containing the contents of the YAML read config file (uses the feature of Extension.rb)
  def read_config filename # {{{

    # Pre-condition check
    raise ArgumentError, "Filename argument should be of type string, but it is (#{filename.class.to_s})" unless( filename.is_a?(String) )

    # Main
    @log.message :debug, "Loading this config file: #{filename.to_s}"
    result = File.open( filename, "r" ) { |file| YAML.load( file ) }                 # return proc which is in this case a hash
    result = hashes_to_ostruct( result ) 

    # Post-condition check
    raise ArgumentError, "The function should return an OpenStruct, but instead returns a (#{result.class.to_s})" unless( result.is_a?( OpenStruct ) )

    result
  end # }}}


  # This function turns a nested hash into a nested open struct
  #
  # @author Dave Dribin
  # Reference: http://www.dribin.org/dave/blog/archives/2006/11/17/hashes_to_ostruct/
  #
  # @param    [Object]    object    Value can either be of type Hash or Array, if other then it is returned and not changed
  # @returns  [OStruct]             Returns nested open structs
  def hashes_to_ostruct object # {{{

    return case object
    when Hash
      object = object.clone
      object.each { |key, value| object[key] = hashes_to_ostruct(value) }
      OpenStruct.new( object )
    when Array
      object = object.clone
      object.map! { |i| hashes_to_ostruct(i) }
    else
      object
    end

  end # of def hashes_to_ostruct }}}

end # of class Vocabulary }}}


# Direct Invocation
if __FILE__ == $0 # {{{
  options = Vocabulary.new.parse_cmd_arguments( ARGV )
  voc     = Vocabulary.new( options )
end # of if __FILE__ == $0 }}}


