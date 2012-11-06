namespace :noosfero do
  namespace :doc do
    def plugins_textiles
      Dir.glob('plugins/**/doc/*.textile')
    end
    task :link_plugins_textiles do
      plugins_textiles.each do |file|
        ln_sf File.join(Rails.root, file), 'doc/noosfero/plugins/'
      end
    end
    task :unlink_plugins_textiles do
      rm_f Dir.glob(File.join(Rails.root, 'doc/noosfero/plugins/*.textile')) -
        [File.join(Rails.root, 'doc/noosfero/plugins/index.textile')]
    end
    input = Dir.glob('doc/noosfero/**/*.textile') + plugins_textiles.map{|i| "doc/noosfero/plugins/#{File.basename(i)}"}
    topics_xhtml = input.map { |item| item.sub('.textile', '.en.xhtml') }.uniq
    sections = Dir.glob('doc/noosfero/*').select {|item| File.directory?(item) }
    toc_sections = sections.map {|item| File.join(item, 'toc.en.xhtml')}
    index_sections = sections.map {|item| File.join(item, 'index.en.xhtml')}

    def build_textile(input, output)
      begin
        require 'redcloth'
        File.open(output ,'w') do |output_file|
          output_file.write(RedCloth.new(File.read(input)).to_html)
          puts "#{input} -> #{output}"
        end
      rescue Exception => e
        rm_f output
        raise e
      end
    end

    topics_xhtml.each do |target|
      source = target.sub('.en.xhtml', '.textile')
      file target => source do |t|
        build_textile(source, target)
      end
    end

    toc_sections.each do |toc|
      section_topics = Dir.glob(File.dirname(toc) + '/*.textile').map {|item| item.sub('.textile', '.en.xhtml') }.reject {|item| ['index.en.xhtml', 'toc.en.xhtml' ].include?(File.basename(item))}
      file toc => section_topics do |t|
        require 'app/models/doc_item'
        require 'app/models/doc_topic'
        begin
          File.open(toc, 'w') do |output_file|
            section = File.basename(File.dirname(toc))
            output_file.puts "<!-- THIS FILE IS AUTOGENERATED. DO NOT EDIT -->"
            output_file.puts "<ul>"
            topics = []
            section_topics.each do |item|
              topics << DocTopic.loadfile(item)
            end
            topics.sort_by { |t| t.order }.each do |topic|
              output_file.puts "<li> <a href=\"/doc/#{section}/#{topic.id}\">#{topic.title}</a> </li>"
            end
            output_file.puts "</ul>"
            puts "#{section_topics.join(', ')} -> #{toc}"
          end
        rescue Exception => e
          rm_rf toc
          raise e
        end
      end
    end

    top_level_toc = 'doc/noosfero/toc.en.xhtml'
    file top_level_toc => index_sections do
      require 'app/models/doc_item'
      require 'app/models/doc_topic'
      begin
        File.open(top_level_toc, 'w') do |output_file|
          output_file.puts "<!-- THIS FILE IS AUTOGENERATED. DO NOT EDIT -->"
          output_file.puts "<ul>"
          index_sections.each do |item|
            section = File.basename(File.dirname(item))
            topic = DocTopic.loadfile(item)
            output_file.puts "<li> <a href=\"/doc/#{section}\">#{topic.title}</a> </li>"
          end
          output_file.puts "</ul>"
        end
      rescue Exception => e
        rm_f top_level_toc
        raise e
      end
    end


    english_xhtml = (topics_xhtml + toc_sections + [top_level_toc])
    task :english => english_xhtml

    po4a_conf = 'tmp/po4a.conf'
    file po4a_conf => english_xhtml do
      require 'noosfero'
      begin
        File.open(po4a_conf, 'w') do |file|
          file.puts "[po4a_langs] #{(Noosfero.locales.keys - ['en']).join(' ')}"
          file.puts "[po4a_paths] po/noosfero-doc.pot $lang:po/$lang/noosfero-doc.po"
          english_xhtml.each do |item|
            file.puts "[type: xhtml] #{item} $lang:#{item.sub(/\.en\.xhtml/, '.$lang.xhtml')}"
          end
        end
      rescue Exception => e
        rm_f po4a_conf
        raise e
      end
    end

    desc "Build Noosfero online documentation"
    task :build => [:link_plugins_textiles, po4a_conf] do
      sh "po4a #{po4a_conf}"
    end

    desc "Cleans Noosfero online documentation"
    task :clean => :unlink_plugins_textiles do
      sh 'rm -f doc/noosfero/*.xhtml'
      sh 'rm -f doc/noosfero/*/*.xhtml'
      rm_f po4a_conf
    end

    desc "Rebuild Noosfero online documentation"
    task :rebuild => [:clean, :build]

    def percent_translated(po_file)
      return 0 unless File.exists?(po_file)
      output = `LANG=C msgfmt --output /dev/null --statistics #{po_file} 2>&1`
      puts output
      translated = (output =~ /([0-9]+) translated messages/) ? $1.to_i : 0
      untranslated = (output =~ /([0-9]+) untranslated messages/) ? $1.to_i : 0
      fuzzy = (output =~ /([0-9]+) fuzzy translations/) ? $1.to_i : 0

      100 * translated / (translated + untranslated + fuzzy)
    end

    desc "Translates Noosfero online documentation (does not touch PO files)"
    task :translate => [:link_plugins_textiles, :do_translation]
    task :do_translation => english_xhtml do
      require 'noosfero'
      languages = Noosfero.locales.keys - ['en']
      languages.each do |lang|
        po = "po/#{lang}/noosfero-doc.po"
        percent = percent_translated(po)
        if percent < 80
          puts "Skipping #{lang} translation, only #{percent}% translated (needs 80%)"
          next
        end
        if File.exists?(po)
          puts "Translating: #{lang}"
          Dir['doc/noosfero/**/*.en.xhtml'].each do |doc|
            target = doc.sub('.en.xhtml', ".#{lang}.xhtml")
            test = "test ! -e #{target} || test #{target} -ot #{doc} || test #{target} -ot #{po}"
            command = "po4a-translate -f xhtml -M utf8 -m #{doc} -p #{po} -L utf8 -l #{target}"
            if system(test)
              unless system("#{command} >/dev/null 2>&1")
                puts "Failed in #{lang} translation!"
                puts "Run the command manually to check:"
                puts "$ #{command}"
                raise "Failed."
              end
              print "."
            else
              print "#"
            end
            $stdout.flush
          end
          puts
        end
      end
    end
  end
end

task :clean => 'noosfero:doc:clean'
