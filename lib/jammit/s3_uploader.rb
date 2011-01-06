require 'mimemagic'

module Jammit
  class S3Uploader
    include AWS::S3

    def initialize(options = {})
      @bucket = options[:bucket]
      unless @bucket
        @bucket_name = options[:bucket_name] || Jammit.configuration[:s3_bucket]
        @access_key_id = options[:access_key_id] || Jammit.configuration[:s3_access_key_id]
        @secret_access_key = options[:secret_access_key] || Jammit.configuration[:s3_secret_access_key]
        @bucket_location = options[:bucket_location] || Jammit.configuration[:s3_bucket_location]
        @cache_control = options[:cache_control] || Jammit.configuration[:s3_cache_control]
        @expires = options[:expires] || Jammit.configuration[:s3_expires]
        @acl = options[:acl] || Jammit.configuration[:s3_permission] || :public_read

        @bucket = find_or_create_bucket
      end
    end

    def upload
      log "Pushing assets to S3 bucket: #{@bucket.name}"
      globs = []

      # add default package path
      if Jammit.gzip_assets
        globs << "public/#{Jammit.package_path}/**/*.gz"
      else
        globs << "public/#{Jammit.package_path}/**/*.css"
        globs << "public/#{Jammit.package_path}/**/*.js"
      end

      # add images
      globs << "public/images/**/*"

      # add custom configuration if defined
      s3_upload_files = Jammit.configuration[:s3_upload_files]
      globs << s3_upload_files if s3_upload_files.is_a?(String)
      globs += s3_upload_files if s3_upload_files.is_a?(Array)

      # upload all the globs
      globs.each do |glob|
        upload_from_glob(glob)
      end
    end

    def upload_from_glob(glob)
      log "Pushing files from #{glob}"
      log "#{ASSET_ROOT}/#{glob}"
      Dir["#{ASSET_ROOT}/#{glob}"].each do |local_path|
        next if File.directory?(local_path)
        remote_path = local_path.gsub(/^#{ASSET_ROOT}\/public\//, "")

        use_gzip = false

        # handle gzipped files
        if File.extname(remote_path) == ".gz"
          use_gzip = true
          remote_path = remote_path.gsub(/\.gz$/, "")
        end

        log "pushing file to s3: #{remote_path}"

        # save to s3
        metadata = {}
        new_object = @bucket.new_object
        new_object.key = remote_path
        new_object.value = open(local_path)
        metadata[:cache_control] = @cache_control if @cache_control
        metadata[:expires] = @expires if @expires
        metadata[:content_encoding] = "gzip" if use_gzip
        new_object.store(metadata)
        new_object.acl.grants << ACL::Grant.grant(@acl.to_sym)
        new_object.acl(new_object.acl)
      end
    end

    def find_or_create_bucket
      AWS::S3::Base.establish_connection!(:access_key_id => @access_key_id, :secret_access_key => @secret_access_key)

      # find or create the bucket
      begin
        Bucket.find(@bucket_name)
      rescue AWS::S3::NoSuchBucket
        log "Bucket not found. Creating '#{@bucket_name}'..."
        Bucket.create(@bucket_name, :access => @acl.to_sym)
        Bucket.find(@bucket_name)
      end
    end

    def log(msg)
      puts msg
    end

  end

end