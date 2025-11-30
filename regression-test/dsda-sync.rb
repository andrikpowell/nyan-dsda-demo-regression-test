#!/usr/bin/env ruby
# spec/dsda-sync.rb
require_relative "support/dsda-common"
include DSDA

require 'optparse'

SCRIPT_DIR = __dir__
DEST_ROOT = File.expand_path('support/demos', SCRIPT_DIR)
FileUtils.mkdir_p(DEST_ROOT)
FileUtils.mkdir_p(File.dirname(DSDA.index_cache_path))
FileUtils.mkdir_p(File.dirname(DSDA.state_cache_path))

options = {
  force: false,
  threads: 1,        # use threads for indexing tool, ruby doesn't like more
  skip_wads: false,
  skip_demos: false,
  refresh_index: false,
  retry_failed: false
}

opt = OptionParser.new
opt.on("--force", "Force overwrite extracted content") { options[:force] = true }
opt.on("--skip-wads", "Don't download/extract wad zips") { options[:skip_wads] = true }
opt.on("--skip-demos", "Don't download/extract demo zips") { options[:skip_demos] = true }
opt.on("--refresh-index", "Ignore cached index and build a new one (recommended: run dsda-index.rb)") { options[:refresh_index] = true }
opt.on("--retry-failed", "Retry only failed demos") { options[:retry_failed] = true }
opt.on("-h","--help"){ puts opt; exit }
opt.parse!(ARGV)

state = DSDA.load_state(DSDA.state_cache_path)

# retry-only path
if options[:retry_failed]
  DSDA.retry_failed_demos(state: state, force: options[:force])
  DSDA.save_state(state)
  exit
end

# load index
index = DSDA.load_index(DSDA.index_cache_path)
if index.nil? && !options[:refresh_index]
  puts "❌ No index cache found. Please run: ruby dsda-index.rb --threads 5"
  exit 1
end

# If refresh_index requested, or index missing, instruct user to run index
if options[:refresh_index]
  puts "❌ Refresh index requested — run dsda-index.rb separately (multi-threaded) and re-run dsda-sync.rb"
  exit 1
end

wad_map = index ? index['wad_map'] : {}

# iterate wads from wad_map or, if a user passed a single wad argument, handle below
ARGV.each do |maybe_wad|
  # user can pass single wad short_name on command line
  if maybe_wad && !maybe_wad.strip.empty?
    # do single-wad sync for that specific wad
    sync_single = true
    single_wad = maybe_wad
  end
end

# Define sync_single_wad here to keep script self-contained and single-threaded
def sync_single_wad(wad_slug, state:, force: false, skip_wads: false, skip_demos: false)
  puts "🔎 Fetching DSDA WAD metadata for: #{wad_slug}"
  wad_meta = nil
  begin
    wad_meta = DSDA.http_get_json("#{DSDA::DSDA_API}/wads/#{URI.encode_www_form_component(wad_slug)}")
  rescue => e
    raise "Failed fetching wad metadata: #{e.message}"
  end

  unless wad_meta.is_a?(Hash)
    raise "Invalid WAD metadata received for #{wad_slug}"
  end

  short = wad_meta['short_name'] || wad_meta['name'] || wad_slug
  wad_name = DSDA.safe_name(short)
  iwad = wad_meta['iwad'] || 'doom2'

  wad_zip_url = (wad_meta['file'] || '').to_s.sub(/^http:/,'https:')
  has_downloadable_wad = !wad_zip_url.strip.empty?

  puts "📦 Found WAD: #{wad_name} (#{short})"
  puts "   IWAD: #{iwad}"
  if has_downloadable_wad
    puts "   ZIP:  #{wad_zip_url}"
  else
    puts "   ZIP:  (none — no downloadable WAD file)"
  end

  wad_root = File.join(DEST_ROOT, iwad, wad_name)
  wad_dir  = File.join(wad_root, "#{wad_name}-wad") # keep wad dir distinct with -wad suffix
  FileUtils.mkdir_p(wad_root)

  # Manual demo area for hand-managed demos; never touched by sync logic
  manual_dir = File.join(wad_root, "manual")
  FileUtils.mkdir_p(manual_dir) unless Dir.exist?(manual_dir)

  zip_filename = nil
  if has_downloadable_wad
    begin
      zip_filename = URI.parse(wad_zip_url).path&.split('/')&.last
    rescue
      zip_filename = nil
    end
  end
  zip_filename ||= "#{wad_name}.zip"
  zip_path = File.join(wad_root, zip_filename)

  unless skip_wads
    if has_downloadable_wad
      if Dir.exist?(wad_dir) && DSDA.content_present?(wad_dir) && !force
        puts "🟢 WAD already extracted, skipping download/extract"
      else
        remote_size = DSDA.http_head_size(wad_zip_url)
        state['wad_meta'] ||= {}
        cached = state['wad_meta'].fetch(short, {})

        if File.exist?(zip_path) && !force && remote_size && File.size(zip_path) == remote_size
          puts "🟢 Found existing zip with matching size — reusing #{zip_path}"
        elsif !remote_size && cached['size'] && File.exist?(zip_path) && !force
          puts "🟢 Reusing existing zip (unknown remote size) - #{zip_path}"
        else
          puts "⬇️ Downloading WAD ZIP..."
          begin
            DSDA.download_file(wad_zip_url, zip_path)
          rescue => e
            raise "Failed to download WAD zip: #{e}"
          end
        end

        # If forcing, clean the wad_dir but *preserve* any existing /extra folder
        if force && Dir.exist?(wad_dir)
          puts "🧹 Cleaning WAD dir (preserving /extra): #{wad_dir}"
          Dir.children(wad_dir).each do |entry|
            # keep extra/ (case-insensitive, just in case)
            next if entry.downcase == "extra"

            path = File.join(wad_dir, entry)
            FileUtils.rm_rf(path)
          end
        end

        begin
          DSDA.extract_with_7z(zip_path, wad_dir)
          DSDA.cleanup_unwanted_files(wad_dir)
        rescue => e
          raise "Extraction failed: #{e}"
        ensure
          File.delete(zip_path) if File.exist?(zip_path)
        end

        state['wad_meta'][short] = {
          'file' => wad_zip_url,
          'size' => DSDA.http_head_size(wad_zip_url),
          'updated_at' => Time.now.utc.iso8601
        }
      end
    else
      FileUtils.mkdir_p(wad_dir)
      puts "🟢 No downloadable WAD file — created metadata folder only."
    end

    # Try to get demo_count from index cache
    cached_index = DSDA.load_index(DSDA.index_cache_path)
    demo_count = cached_index ? (cached_index['wad_map'][short]&.length || 0) : 0

    info_path = File.join(wad_dir, "DSDA-info.txt")
    DSDA.write_dsda_info(info_path, {
      "Name"        => (wad_meta['name'] || wad_name),
      "ShortName"   => short,
      "IWAD"        => iwad,
      "DSDA WAD ID" => (wad_meta['id'].to_s.strip.empty? ? "(none)" : wad_meta['id'].to_s),
      "URL"         => "https://dsdarchive.com/wads/#{short}",
      "Authors"     => Array(wad_meta['author'] || wad_meta['authors']).join(", "),
      "Total demos" => demo_count,
      "Notes"       => (wad_meta['description'] || "")
    })
    puts "📝 WAD DSDA-info.txt written to #{info_path}"
    state['done_wads'][short] = true
    DSDA.save_state(state, DSDA.state_cache_path)
  end

  unless skip_demos
    puts "🔎 Fetching demos list for wad=#{wad_slug}..."
    page = 1
    demos = []
    loop do
      url = "#{DSDA::DSDA_API}/demos?wad=#{URI.encode_www_form_component(wad_slug)}&per=#{DSDA::PER_PAGE}&page=#{page}"
      data = DSDA.http_get_json(url)
      break if data.nil? || data['demos'].nil? || data['demos'].empty?
      demos.concat(data['demos'])
      break if data['demos'].length < (data['per'] || DSDA::PER_PAGE)
      page += 1
    end

    puts "📊 Found #{demos.length} demo entries for #{wad_slug}"

    demos.each_with_index do |demo, idx|
      demo ||= {}
      demo_id = demo['id'] || "unknown_#{idx}"
      zip_url = (demo['file'] || '').to_s.sub(/^http:/,'https:')
      zip_name  = File.basename(zip_url) rescue "demo_#{demo_id}.zip"
      demo_base = File.basename(zip_name, ".zip")

      # Raw ZIP-derived folder name
      demo_base = File.basename(zip_name, ".zip")

      # Final folder name that demos will be merged into
      merged_demo_folder = File.join(wad_root, demo_base)

      # Temporary extraction area (always unique)
      temp_demo_folder = File.join(wad_root, "#{demo_base}__tmp_#{demo_id}")

      engine = demo['engine'].to_s

      if DSDA.engine_should_skip?(engine)
        puts "⚠️ Skipping demo (unsupported engine: #{engine}) #{zip_name}"
        state['done_demos'][demo_id.to_s] = "skipped_engine:#{engine}"
        DSDA.save_state(state, DSDA.state_cache_path)
        next
      end

      # If we already processed this demo_id and the merged folder has content,
      # we can safely skip (re-running the sync) unless forcing.
      if state['done_demos'][demo_id.to_s] && DSDA.content_present?(merged_demo_folder) && !force
        puts "🟢 Demo #{zip_name} already processed — skipping"
        next
      end

      # Prepare fresh temp folder
      FileUtils.rm_rf(temp_demo_folder) if Dir.exist?(temp_demo_folder)
      FileUtils.mkdir_p(temp_demo_folder)

      tmp_zip = File.join(wad_root, zip_name)

      max_retries = 10
      attempt = 0
      begin
        puts "⬇️ (#{idx+1}/#{demos.length}) Downloading demo: #{zip_name} (attempt #{attempt+1}/#{max_retries})"
        DSDA.download_file(zip_url, tmp_zip)
      rescue => e
        attempt += 1
        if attempt < max_retries
          sleep_time = [0.5 * attempt, 5].min
          puts "⚠️  Download failed: #{e.message}. Retrying in #{sleep_time}s..."
          sleep sleep_time
          retry
        else
          warn "❌ Permanently failed to download demo #{zip_name} after #{max_retries} attempts"
          state['failed_demos'][demo_id.to_s] = "download_error:#{e}"
          DSDA.save_state(state, DSDA.state_cache_path)
          next
        end
      end

      begin
        puts "📂 Extracting demo → #{temp_demo_folder}"
        FileUtils.rm_rf(temp_demo_folder) if force && Dir.exist?(temp_demo_folder)
        DSDA.extract_with_7z(tmp_zip, temp_demo_folder)
        DSDA.cleanup_unwanted_files(temp_demo_folder)
        File.delete(tmp_zip) if File.exist?(tmp_zip)

        # Write demo-specific DSDA-info.txt into the *temp* folder
        DSDA.write_dsda_info(File.join(temp_demo_folder, "DSDA-info.txt"), {
          "WAD"     => wad_name,
          "Level"   => demo['level'],
          "Category"=> demo['category'],
          "Players" => Array(demo['players']).join(", "),
          "Engine"  => demo['engine'],
          "TAS"     => demo['tas'].to_s,
          "Time"    => demo['time'],
          "URL"     => "https://dsdarchive.com/wads/#{short}"
        })

        # Merge temp folder into the final merged folder
        DSDA.merge_demo_dir(temp_demo_folder, merged_demo_folder)
        puts "📝 Merged demo into #{merged_demo_folder}"

        state['done_demos'][demo_id.to_s] = "ok"
        DSDA.save_state(state, DSDA.state_cache_path)
      rescue => e
        warn "⚠️ Failed extracting/merging demo #{zip_name}: #{e}"
        state['failed_demos'][demo_id.to_s] = "extract_error:#{e}"
        DSDA.save_state(state, DSDA.state_cache_path)
        # keep tmp_zip for inspection
      ensure
        # Always clean up temp folder
        FileUtils.rm_rf(temp_demo_folder) if Dir.exist?(temp_demo_folder)
      end
    end
  end
end

# Main entry:
if ARGV.length == 1 && !ARGV[0].strip.empty?
  # single wad mode
  wad_short = ARGV[0].strip
  puts "ℹ️ Single WAD mode: #{wad_short} (force=#{!!options[:force]})"
  sync_single_wad(wad_short, state: state, force: !!options[:force], skip_wads: options[:skip_wads], skip_demos: options[:skip_demos])
else
  # full sync using cached index
  if index.nil?
    puts "❌ No index cache to drive full sync. Run: ruby dsda-index.rb --threads 5"
    exit 1
  end

  wad_map = index['wad_map']
  processed = 0
  errors = 0

  wad_map.each do |wad_short, demos|
    begin
      puts "\n────────────────────────────────────────"
      puts "Syncing wad: #{wad_short} (#{demos.length} demos)"
      sync_single_wad(wad_short, state: state, force: options[:force], skip_wads: options[:skip_wads], skip_demos: options[:skip_demos])
    rescue Interrupt
      puts "\n✋ Interrupted by user. State saved."
      DSDA.save_state(state, DSDA.state_cache_path)
      exit
    rescue => e
      errors += 1
      puts "⚠️  Skipping wad #{wad_short} due to error: #{e.message}"
    end
    processed += 1
  end

  state['last_sync'] = Time.now.utc.iso8601
  DSDA.save_state(state, DSDA.state_cache_path)
  puts "\n✅ FULL SYNC complete. Wads processed: #{processed}, errors: #{errors}"
end
