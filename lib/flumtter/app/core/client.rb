require 'twitter'

module Flumtter
  class Client
    class NoSetAccount < StandardError; end

    include Util
    attr_reader :account, :sthread, :ethread, :rest

    @@events = []
    def self.on_event(*filter,&blk)
      @@events << [filter, blk]
    end

    def callback(object, events=nil)
      events ||= object.type(@account)
      @@events.each do |filter, blk|
        blk.call(object, self) if (filter - events).empty?
      end
    end

    def initialize(account)
      debug if Setting[:debug]
      @queue = Queue.new
      @mutex = Mutex.new
      set(account)
      Cli.run(self)
      start
      Keyboard.input(self)
    rescue NoSetAccount
      STDERR.puts "Error: Account Not Found".color
      exit
    end

    def set(account)
      raise NoSetAccount if account.nil?
      @account = account
      @rest = Twitter::REST::Client.new(@account.keys)
      @stream = Twitter::Streaming::Client.new(@account.keys)
    end

    def start
      Flumtter.callback(:init, self)
      stream unless Setting[:non_stream]
    end

    def stream
      execute
      @sthread = Thread.new do
        puts "#{@account.screen_name}'s stream_start!"
        "#{@account.screen_name} #{TITLE}".title
        begin
          @stream.user(Setting[:stream_option] || {}) do |object|
            @queue.push object
          end
        rescue Twitter::Error::TooManyRequests => e
          puts e.class.to_s.color
        end
      end
    end

    def execute
      @ethread = Thread.new do
        loop do
          handler do
            object = @queue.pop
            begin
              @mutex.lock
              callback(object)
            ensure
              @mutex.unlock
            end
          end
        end
      end
    end

    def kill
      @sthread.kill
      @ethread.kill
      @queue.clear
    end

    def pause
      @mutex.lock
    end

    def resume
      @mutex.unlock
    end

    private
    def handler
      yield
    rescue => e
      error e
    rescue Exception => e
      error e
      raise e
    end

    def debug
      update = %i(update update_with_media retweet block unblock create_direct_message follow unfollow favorite unfavorite)
      Twitter::REST::Client.class_eval do
        update.each do |sym|
          define_method sym do |*args|
            puts "Debug: :#{sym} #{args}"
            sleep 1
          end
        end
      end
    end
  end
end

class Twitter::Tweet
  def type(account)
    type = [:tweet]
    type << (retweet? ? :retweet : :retweet!)
    type << (user.id == account.id ? :self_tweet : :self_tweet!)
    type << (reply? ? :reply : :reply!)
    type << (quote? ? :quote : :quote!)
    type << (in_reply_to_user_id == account.id ? :reply_to_me : :reply_to_me!)
    type
  end

  def via
    source.gsub(/<(.+)\">/,"").gsub(/<\/a>/,"")
  end
end

class Twitter::Streaming::Event
  def type(account)
    [:event, name]
  end
end

class Twitter::Streaming::FriendList
  def type(account)
    [:friendlist]
  end
end

class Twitter::Streaming::DeletedTweet
  def type(account)
    [:deletedtweet]
  end
end

class Twitter::DirectMessage
  def type(account)
    type = [:directmessage]
    type << (sender.id == account.id ? :self_message : :self_message!)
  end
end
