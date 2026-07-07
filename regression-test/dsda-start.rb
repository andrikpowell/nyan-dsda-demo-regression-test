#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'json'
require 'time'
require 'rbconfig'
require 'shellwords'
require_relative 'support/dsda-common'
require_relative 'support/dsda-test-prefs'
include DSDA

$stdout.sync = true
SCRIPT_DIR = __dir__

COMMANDS = {
  'index' => File.join(SCRIPT_DIR, 'dsda-index.rb'),
  'sync'  => File.join(SCRIPT_DIR, 'dsda-sync.rb'),
  'test'  => File.join(SCRIPT_DIR, 'dsda-test.rb')
}.freeze

def load_last_sync
  state = load_sync_state
  value = state['last_sync']
  return nil if value.to_s.strip.empty?

  Time.parse(value).localtime
rescue
  nil
end

def load_sync_state
  path = DSDA.state_cache_path
  return {} unless File.exist?(path)

  JSON.parse(File.read(path))
rescue
  {}
end

def index_available?
  File.exist?(DSDA.index_cache_path) && !DSDA.load_index.nil?
rescue
  false
end

def sync_done?
  !!load_last_sync
end

def sync_failures?
  state = load_sync_state
  state.fetch('failed_wads', {}).any? || state.fetch('failed_demos', {}).any?
end

def test_failed?
  if File.exist?(DSDA.test_state_path)
    state = JSON.parse(File.read(DSDA.test_state_path))
    return state['status'].to_s == 'fail'
  end

  count_csv_rows(FAILURES_OUTPUT).positive?
rescue
  count_csv_rows(FAILURES_OUTPUT).positive?
end

def format_dashboard_time(time)
  time ? time.strftime('%Y-%m-%d %I:%M %p') : 'never'
end

def count_csv_rows(path)
  return 0 unless File.exist?(path)

  CSV.foreach(path, headers: true).count
rescue
  0
end

def last_test_result
  state =
    if File.exist?(DSDA.test_state_path)
      JSON.parse(File.read(DSDA.test_state_path))
    end

  if state
    scope = state['scope'].to_s
    failed = state['failed'].to_i
    total = state['total'].to_i
    status = state['status'].to_s
    suffix = scope.empty? ? '' : " (#{scope}, #{total} demos)"

    return status == 'pass' ? green("pass#{suffix}") : red("fail#{suffix}, #{failed} failed")
  end

  failure_count = count_csv_rows(FAILURES_OUTPUT)
  if failure_count.positive?
    red("fail (#{failure_count} failure#{'s' if failure_count != 1})")
  elsif File.exist?(CSV_OUTPUT)
    green('pass')
  else
    yellow('unknown')
  end
end

def print_dashboard
  puts
  puts
  puts rainbow('DSDA Regression Test', offset: 0, span: 112)
  puts "----------------------------------------"
  puts
  puts "Last sync: #{format_dashboard_time(load_last_sync)}"
  puts "Last test result: #{last_test_result}"
  puts
  puts 'Type the program you would like to run:'
  puts '  index [options]            -   Get the current DSDA Archive demo database'
  puts '  sync  [selector/options]   -   Download demos and WADs from the DSDA Archive'
  puts '  test  [selector/options]   -   Run the current exe against demos, with regression exe comparison'
  puts
  puts 'Use -h or --help after a program name for advanced parameters.'
  puts 'Type "q" / "exit" to close.'
  puts
end

def run_program(command, args)
  script = COMMANDS[command]
  unless script
    puts red("Unknown command: #{command}")
    return false
  end

  puts
  puts orange("Running: ruby #{File.basename(script)} #{args.join(' ')}".strip)
  puts
  $stdout.flush

  Dir.chdir(SCRIPT_DIR) do
    system(RbConfig.ruby, script, *args)
  end
end

def prompt_yes_no(message)
  loop do
    puts
    puts yellow(message)
    $stdout.write('y or n > ')
    $stdout.flush

    input = STDIN.gets
    return false unless input

    case input.strip.downcase
    when 'y', 'yes'
      return true
    when 'n', 'no', ''
      return false
    else
      puts "Please enter y or n."
    end
  end
end

def help_args?(args)
  args.any? { |arg| DSDA.help_flag?(arg) || %w[help ?].include?(arg.to_s.downcase) }
end

def press_enter_to_continue
  puts
  $stdout.write(yellow('Press Enter to return...'))
  $stdout.flush
  STDIN.gets
end

def guided_startup
  unless index_available?
    if prompt_yes_no('DSDA index database not found. Would you like to index the current database?')
      run_program('index', [])
    end
  end

  if index_available? && !sync_done?
    if prompt_yes_no("You haven't done a DSDA sync before. Would you like to do a full sync now?")
      run_program('sync', [])
    end
  end

  if sync_failures?
    if prompt_yes_no('Seems the sync has failed for one or more demos. Would you like to retry syncing failed demos?')
      run_program('sync', ['--failed-only'])
    end
  end
end

def post_run_prompts(command, args)
  failed_only = args.any? { |arg| %w[--retry-failed --failed-only].include?(arg) }
  compare = args.any? { |arg| %w[--compare].include?(arg) }

  if command == 'sync' && !failed_only && sync_failures?
    if prompt_yes_no('Seems the sync has failed for one or more demos. Would you like to retry syncing failed demos?')
      run_program('sync', ['--failed-only'])
    end
  end

  if command == 'test' && !failed_only && test_failed?
    puts
    puts red('Seems the demo test failed. Please take a look at failures.csv, and check your port or overrides.csv.')
    if prompt_yes_no('Would you like to re-test the failed demos?')
      retry_args = ['--failed-only']
      retry_args << '--compare' if compare
      run_program('test', retry_args)
    end
  end
end

def handle_command(words, interactive: false)
  command = words.shift.to_s.downcase
  return :continue if command.empty?
  return :exit if %w[exit quit q].include?(command)

  if DSDA.help_flag?(command) || %w[help ?].include?(command)
    print_dashboard
    return :continue
  end

  run_program(command, words)
  press_enter_to_continue if interactive && help_args?(words)
  post_run_prompts(command, words) if interactive
  press_enter_to_continue if interactive && command == 'test' && !help_args?(words)
  :continue
end

if ARGV.any?
  exit(handle_command(ARGV.dup) == :exit ? 0 : ($?.respond_to?(:exitstatus) ? $?.exitstatus.to_i : 0))
end

begin
  guided_startup

  loop do
    print_dashboard
    $stdout.write('> ')
    $stdout.flush
    input = STDIN.gets
    break unless input

    words =
      begin
        Shellwords.split(input)
      rescue ArgumentError => e
        puts red("Input error: #{e.message}")
        next
      end

    status = handle_command(words, interactive: true)
    break if status == :exit
  end
rescue Interrupt
  puts
  puts yellow('Interrupted.')
end

puts 'Bye.'
