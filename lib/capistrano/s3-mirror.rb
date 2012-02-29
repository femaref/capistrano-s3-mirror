begin
  require "aws/s3"
rescue LoadError
  puts "aws-s3 gem needs to be installed"
  puts "install via 'gem i aws-s3'"
end

unless Capistrano::Configuration.respond_to?(:instance)
  abort "capistrano/ext/multistage requires Capistrano 2"
end

Capistrano::Configuration.instance.load do
  namespace :deploy do
    desc "mirrors the content of the public folder to amazon s3"
    task :s3_mirror do
    
      if !exists? :s3_access_key_id
        set(:s3_access_key_id) do
          Capistrano::CLI.ui.ask("Enter s3_access_key_id: ")
        end
      end
      
      if !exists? :s3_secret_access_key
        set(:s3_secret_access_key) do
          Capistrano::CLI.password_prompt("Enter s3_secret_access_key: ")
        end
      end
      
      if !exists? :s3_bucket_name
        set(:s3_bucket_name) do
          Capistrano::CLI.ui.ask("Enter s3_bucket_name: ")
        end
      end
      
      if !exists? :s3_base_path
        set(:s3_base_path) do
          Capistrano::CLI.ui.ask("Enter s3_base_path: ")
        end
      end
      
      sync s3_access_key_id, s3_secret_access_key, s3_bucket_name, s3_base_path
      
    end
  end
end

def sync (key_id, secret_access_key, bucket_name, base_path)
  # TODO: make changeable
  AWS::S3::DEFAULT_HOST.replace("s3-eu-west-1.amazonaws.com")
  AWS::S3::Base.establish_connection!(:access_key_id => key_id, :secret_access_key => secret_access_key)
  
  bucket = AWS::S3::Bucket.find(bucket_name)
  
  #/bucket_name/path/to/File
  #/path/to/file
  
  context = File.join(bucket_name, base_path).split("/")
  
  # filter out directories
  remote_data = bucket.objects.select{ |object| object.content_type != "application/x-directory"}
  # remove the bucket name from the path
  remote_data = remote_map(remote_data, context)
  remote = Hash[remote_data]
  
  local_data = Dir.chdir("public") do
    # map local files to path => md5(file)
    Dir["**/**"].select{ |d| !File.directory? d }.map { |path| [ path, Digest::MD5.file(path).hexdigest ] }
  end
  local = Hash[local_data]
  
  new = local.keys - remote.keys
  deleted = remote.keys - local.keys
  both = local.keys & remote.keys
  
  uploaded_count = 0
  deleted_count = 0
  updated_count = 0
  
  Dir.chdir("public") do
    new.each do |entry|
      AWS::S3::S3Object.store(entry, open(entry), bucket_name, :access => :public_read)
      uploaded_count += 1
    end
    
    deleted.each do |entry|
      object = AWS::S3::S3Object.find(entry, bucket_name)
      object.delete
      
      deleted_count += 1
    end
    
    both.each do |entry|
      if local[entry] != remote[entry].etag
        AWS::S3::S3Object.store(entry, open(entry), bucket_name)
        
        updated_count += 1
      end
    end
  end

  puts "uploaded #{uploaded_count}, deleted #{deleted_count}, updated #{updated_count}"
  
end

def remote_map (remote_data, context)
  remote_data.map do |object|
    cur_path = object.path.split("/")
    
    if cur_path[0] == ""
      cur_path = cur_path.drop(1)
    end
    
    cur_context = context.clone
    
    cur_path = cur_path.drop_while do |element|
      element == cur_context.shift
    end
    
    if cur_context.count > 0
      abort "file error: didn't fit the bucket/base/path description, offending path: #{object.path}"
    end
    
    [File.join(cur_path), object]
  end
end