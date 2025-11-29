# frozen_string_literal: true
# spec/lib/dsda_common.rb
require 'net/http'
require 'uri'
require 'json'
require 'fileutils'
require 'time'
require 'rbconfig'
require 'thread'

module DSDA
  DSDA_API = "https://dsdarchive.com/api"
  USER_AGENT = "NYAN-DSDA-SYNC/1.0"
  PER_PAGE = 200

  # caches/state paths (consumer may override if desired)
  def self.state_cache_path(base_dir = __dir__ + '/..')
    File.expand_path('cache/dsda_sync_state.json', base_dir)
  end

  def self.index_cache_path(base_dir = __dir__ + '/..')
    File.expand_path('cache/dsda_demo_index.json', base_dir)
  end

  # engines to skip
  SKIP_ENGINE_PATTERNS = [
    /gzdoom/i, /zdoom/i, /lzdoom/i, /doom\s*legacy/i,
    /vbdoom/i, /doom64ex/i, /k8vavoom/i, /qdoom/i
  ]

  JSON_MUTEX = Mutex.new
  INDEX_WRITE_MUTEX = Mutex.new

  def self.json_generate_safe(obj)
    JSON_MUTEX.synchronize { JSON.generate(obj) }
  end

  def self.save_index(wad_map, per: PER_PAGE, path: index_cache_path)
    INDEX_WRITE_MUTEX.synchronize do
      header = {
        'indexed_at' => Time.now.utc.iso8601,
        'per'        => per,
        'format'     => 'ndjson-v1'
      }

      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

      tmp = "#{path}.tmp"
      File.open(tmp, "w") do |f|
        # write header (compact JSON)
        f.puts(json_generate_safe(header))

        # write demo lines (compact JSON)
        wad_map.each do |wad, demos|
          demos.each do |demo|
            f.puts(json_generate_safe({ "wad" => wad, "demo" => demo }))
          end
        end
      end

      # Atomic replace
      File.rename(tmp, path)
    end
  end

  def self.json_parse_safe(str)
    JSON_MUTEX.synchronize do
      JSON.parse(str)
    end
  end

  def self.json_dump_safe(obj)
    JSON_MUTEX.synchronize do
      JSON.pretty_generate(obj)
    end
  end

  def self.atomic_write(path, content)
    dir = File.dirname(path)
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
    tmp = "#{path}.tmp"
    File.write(tmp, content)
    File.rename(tmp, path)
  end

  def self.safe_name(s)
    s.to_s.strip.gsub(/[^\w\-.]+/,'_')
  end

  def self.engine_should_skip?(engine)
    return false if engine.nil? || engine.to_s.strip.empty?
    SKIP_ENGINE_PATTERNS.any? { |pat| engine =~ pat }
  end

  def self.detect_7z
    host_os = RbConfig::CONFIG['host_os'].downcase
    candidates = if host_os =~ /mswin|mingw|cygwin/
      ['C:\\Program Files\\7-Zip\\7z.exe','C:\\Program Files (x86)\\7-Zip\\7z.exe','7z']
    else
      ['7zz','7z','/usr/local/bin/7z','/opt/homebrew/bin/7z']
    end
    candidates.map(&:to_s).map{|p| p.strip.gsub('"','') }.find do |p|
      if %w[7z 7zz].include?(p)
        (system("#{p} --help >NUL 2>&1") rescue false) || (system("which #{p} > /dev/null 2>&1") rescue false)
      else
        File.exist?(p)
      end
    end
  end

  SEVEN_ZIP = detect_7z
  unless SEVEN_ZIP
    raise "7z not found. Install 7-Zip or p7zip and ensure `7z`/`7zz` is on PATH."
  end
  SEVEN_ZIP_BIN = %Q["#{SEVEN_ZIP}"]

  def self.http_get_json(url)
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req['User-Agent'] = USER_AGENT
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      res = http.request(req)
      if res.code.to_i == 200
        begin
          return json_parse_safe(res.body)
        rescue JSON::ParserError => e
          raise "JSON parse error for #{url} → maybe HTML (#{e.message})"
        end
      else
        raise "HTTP #{res.code} for #{url}"
      end
    end
  end

  def self.write_dsda_info(path, map)
    FileUtils.mkdir_p(File.dirname(path)) unless Dir.exist?(File.dirname(path))

    File.open(path, 'w') do |f|
      f.puts "[DSDA INFO]"
      map.each do |k, v|
        f.puts "#{k}: #{v}"
      end
    end
  end

  def self.http_head_size(url)
    return nil if url.nil? || url.to_s.strip.empty?
    uri = URI(url)
    req = Net::HTTP::Head.new(uri)
    req['User-Agent'] = USER_AGENT
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      res = http.request(req)
      return res['content-length']&.to_i if res.code.to_i == 200
    end
  rescue
    nil
  end

  def self.download_file(url, dest)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme=='https') do |http|
      http.request_get(uri.path + (uri.query ? "?#{uri.query}" : "")) do |resp|
        open(dest, "wb") do |io|
          resp.read_body { |chunk| io.write(chunk) }
        end
      end
    end
  end

  def self.retry_failed_demos(state:, force: false)
    failed = state["failed_demos"] || {}
    return puts "No failed demos to retry." if failed.empty?

    puts "🔁 Retrying #{failed.size} failed demos..."

    # Group failed demo IDs by WAD
    wad_groups = Hash.new { |h,k| h[k] = [] }

    failed.keys.each do |demo_id|
      # fetch metadata to recover wad + zip
      begin
        meta = http_get_json("#{DSDA_API}/demos/#{demo_id}")
      rescue => e
        puts "❌ Cannot fetch demo #{demo_id} metadata: #{e.message}"
        next
      end

      wad = meta["wad"].to_s
      wad_groups[wad] << [demo_id, meta]
    end

    wad_groups.each do |wad, entries|
      puts "\n🔄 Retrying wad=#{wad} (#{entries.size} demos)"

      wad_meta = http_get_json("#{DSDA_API}/wads/#{URI.encode_www_form_component(wad)}")
      short = wad_meta["short_name"] || wad
      iwad  = wad_meta["iwad"] || "doom2"

      wad_root = File.join(File.expand_path("..", __dir__), "support/demos", iwad, short)
      FileUtils.mkdir_p(wad_root)

      entries.each do |demo_id, meta|
        zip_url = meta["file"].to_s.sub(/^http:/, "https:")
        zip_name = File.basename(zip_url) rescue "#{demo_id}.zip"
        demo_base = File.basename(zip_name, ".zip")

        puts "   ↻ demo #{demo_id}"
        puts "     ⬇️ retry downloading..."

        tmp_zip = File.join(wad_root, zip_name)
        demo_folder = File.join(wad_root, "#{demo_id}_#{demo_base}")

        FileUtils.rm_rf(demo_folder) if force && Dir.exist?(demo_folder)
        FileUtils.mkdir_p(demo_folder)

        begin
          download_file(zip_url, tmp_zip)
        rescue => e
          puts "     ❌ still failing: #{e.message}"
          next
        end

        begin
          extract_with_7z(tmp_zip, demo_folder)
          cleanup_unwanted_files(demo_folder)
          File.delete(tmp_zip) if File.exist?(tmp_zip)
        rescue => e
          puts "     ❌ extraction still failing: #{e.message}"
          next
        end

        puts "     ✅ success!"
        state["done_demos"][demo_id.to_s] = "ok"
        state["failed_demos"].delete(demo_id.to_s)
      end
    end
  end

  def self.extract_with_7z(zip_path, dest)
    FileUtils.mkdir_p(dest)
    cmd = "#{SEVEN_ZIP_BIN} x \"#{zip_path}\" -o\"#{dest}\" -y >NUL 2>&1"
    puts "📂 Extracting #{File.basename(zip_path)} → #{dest} (via 7-Zip)"
    raise "Extraction failed for #{zip_path}" unless system(cmd)
    puts "🧰 Extracted successfully."
  end

  def self.cleanup_unwanted_files(dir)
    Dir.glob(File.join(dir,'**','*.exe')).each do |f|
      begin
        File.delete(f)
        puts "🧹 Removed EXE: #{f}"
      rescue => e
        puts "⚠️ Could not delete #{f}: #{e.message}"
      end
    end
  end

  def self.content_present?(dir)
    ['**/*.wad','**/*.lmp','**/*.deh','**/*.bex','**/*.txt'].any? { |g| Dir.glob(File.join(dir,g)).any? }
  end

  # state helpers
  def self.load_state(path = state_cache_path)
    return { "last_sync" => nil, "done_wads" => {}, "done_demos" => {}, "failed_demos" => {}, "wad_meta" => {} } unless File.exist?(path)
    begin
      json_parse_safe(File.read(path))
    rescue => _
      { "last_sync" => nil, "done_wads" => {}, "done_demos" => {}, "failed_demos" => {}, "wad_meta" => {} }
    end
  end

  def self.save_state(state, path = state_cache_path)
    atomic_write(path, json_dump_safe(state))
  end

  # index helpers
  def self.load_index(path = index_cache_path)
    return nil unless File.exist?(path)

    raw = File.read(path)
    return nil if raw.strip.empty?

    lines = raw.lines

    # --- DETECT FORMATS ------------------------------------------------------

    # Case 1: Old JSON index (single JSON object)
    # Heuristic: entire file starts with { AND ends with }
    # AND contains "wad_map" INSIDE the object.
    if lines.length == 1 && raw.lstrip.start_with?("{") && raw.rstrip.end_with?("}")
      begin
        warn "ℹ️ Converting old JSON index → NDJSON format..."
        data = json_parse_safe(raw)
        wad_map = data["wad_map"]

        if wad_map.is_a?(Hash)
          save_index(wad_map, per: data["per"], path: path)
          return load_index(path)
        else
          warn "⚠️ 'wad_map' missing in old JSON format"
          return nil
        end
      rescue => e
        warn "⚠️ Old JSON index is corrupt: #{e.message}"
        return nil
      end
    end

    # Case 2: NDJSON format (1 header + many demo lines)
    # NDJSON ALWAYS has ≥2 lines.
    if lines.length >= 2
      begin
        header = json_parse_safe(lines[0])
        return nil unless header.is_a?(Hash) && header["indexed_at"]

        wad_map = Hash.new { |h,k| h[k] = [] }

        lines[1..].each_with_index do |line, idx|
          stripped = line.strip
          next if stripped.empty?
          next unless stripped.start_with?("{")   # skip garbage or accidental text

          begin
            obj = json_parse_safe(stripped)
          rescue => e
            warn "⚠️ NDJSON parse error on line #{idx+2}: #{e.message}"
            next
          end

          wad  = obj["wad"]
          demo = obj["demo"]
          next if wad.nil? || demo.nil?

          wad_map[wad] << demo
        end

        return {
          "indexed_at" => header["indexed_at"],
          "per"        => header["per"],
          "wad_map"    => wad_map
        }
      rescue => e
        warn "⚠️ NDJSON index parse error: #{e.message}"
        return nil
      end
    end

    warn "⚠️ Unrecognized index format — ignoring."
    nil
  end

  # fast index function (can be multi-threaded)
  def self.fast_index_all_pages(total_pages, threads: 5, max_retries: 5)
    wad_map = Hash.new { |h,k| h[k] = [] }
    mutex   = Mutex.new
    work_q  = Queue.new
    (1..total_pages).each { |p| work_q << [p, 0] }   # [page, attempts]

    workers = Array.new(threads) do
      Thread.new do
        loop do
          begin
            page, attempt = work_q.pop(true)
          rescue ThreadError
            break
          end

          url = page == 1 ? "#{DSDA_API}/demos?per=#{PER_PAGE}" : "#{DSDA_API}/demos?per=#{PER_PAGE}&page=#{page}"
          begin
            data = http_get_json(url)
          rescue => e
            puts "❌ Page #{page} failed (attempt #{attempt+1}/#{max_retries}): #{e.message}"
            if attempt + 1 < max_retries
              sleep(0.3 * (attempt + 1))
              work_q << [page, attempt + 1]
            else
              puts "🚫 Page #{page} permanently failed after #{max_retries} attempts."
            end
            next
          end

          demos = data["demos"]
          if demos.nil? || demos.empty?
            puts "⚠️ Page #{page} returned empty result"
            next
          end

          mutex.synchronize do
            demos.each { |d| wad_map[d["wad"].to_s] << d }
          end

          puts "  page #{page} ✓ (#{demos.length})"
        end
      end
    end

    workers.each(&:join)
    wad_map
  end

  # For LMP conflict: if same name but different size, generate new name
  # foo.lmp → foo_2.lmp → foo_3.lmp etc.
  def self.next_available_filename(dest_dir, base)
    ext  = File.extname(base)
    stem = File.basename(base, ext)
    name = base
    counter = 2

    while File.exist?(File.join(dest_dir, name))
      name = "#{stem}_#{counter}#{ext}"
      counter += 1
    end

    name
  end

  # Merge temporary extracted demo folder into the final merged folder.
  # Mirrors dsda-fix.rb behavior: merge .lmp + append dsda-info.txt blocks.
  def self.merge_demo_dir(src, dest)
    FileUtils.mkdir_p(dest)

    # 1) merge .lmp files
    Dir.glob(File.join(src, "*.lmp")).each do |lmp|
      base      = File.basename(lmp)
      dest_file = File.join(dest, base)

      if File.exist?(dest_file)
        # identical size → assume duplicate; skip
        if File.size(lmp) == File.size(dest_file)
          next
        else
          # conflict → rename incoming file
          new_name = next_available_filename(dest, base)
          puts "      ⚠️ Conflict: #{base} → #{new_name}"
          FileUtils.cp(lmp, File.join(dest, new_name))
        end
      else
        FileUtils.cp(lmp, dest_file)
      end
    end

    # 2) merge dsda-info.txt (append block)
    src_info = File.join(src, "DSDA-info.txt")
    if File.exist?(src_info)
      dest_info = File.join(dest, "DSDA-info.txt")
      if File.exist?(dest_info)
        File.open(dest_info, "a") do |f|
          f.puts "\n\n" + File.read(src_info)
        end
      else
        FileUtils.cp(src_info, dest_info)
      end
    end
  end
end
