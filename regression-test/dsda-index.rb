#!/usr/bin/env ruby
# spec/dsda-index.rb
require_relative "support/dsda-common"
include DSDA

require 'optparse'
options = { threads: 5, max_retries: 5, per: DSDA::PER_PAGE }

opt = OptionParser.new
opt.on("--threads N", Integer, "Indexing threads (default 5)") { |v| options[:threads] = v }
opt.on("--per N", Integer, "Per-page (default 200)") { |v| options[:per] = v }
opt.on("--max-retries N", Integer, "Retries per page") { |v| options[:max_retries] = v }
opt.on("-h", "--help") { puts opt; exit }
opt.parse!(ARGV)

puts "🔎 Fetching first page to compute total_pages..."
first_url = "#{DSDA::DSDA_API}/demos?per=#{options[:per]}"
first_data = DSDA.http_get_json(first_url)

total_pages = first_data["total_pages"] || ((first_data["total_demos"] || 0) / options[:per].to_f).ceil
total_pages = 1 if total_pages.nil? || total_pages < 1
puts "ℹ️ Full index mode: total_pages=#{total_pages} (per=#{options[:per]})"

start = Time.now
puts "🚀 Parallel indexing using #{options[:threads]} threads..."
wad_map = DSDA.fast_index_all_pages(total_pages, threads: options[:threads], max_retries: options[:max_retries])

DSDA.save_index(wad_map, per: options[:per])
elapsed = Time.now - start
puts "💾 Saved index cache to #{DSDA.index_cache_path}"
puts "✅ Indexing complete — wads: #{wad_map.keys.length}, time: #{elapsed.round(1)}s"
