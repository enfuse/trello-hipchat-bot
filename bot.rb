#!/usr/bin/env ruby
require 'bundler'
Bundler.require

require 'time'
require 'pp'
require 'dedupe'

Trello.configure do |config|
  config.developer_public_key = ENV['TRELLO_OAUTH_PUBLIC_KEY']
  config.member_token = ENV['TRELLO_TOKEN']
end

class Bot

  def self.run

    hipchat = HipChat::Client.new(ENV["HIPCHAT_API_TOKEN"])

    dedupe = Dedupe.new

    hipchat_rooms = ENV["HIPCHAT_ROOM"].split(',')
    boards = ENV["TRELLO_BOARD"].split(',').each_with_index.map {|board, i| [Trello::Board.find(board), hipchat_rooms[i]] }
    now = Time.now.utc
    timestamps = {}

    boards.each do |board_with_room|
      timestamps[board_with_room.first.id] = now
    end

    scheduler = Rufus::Scheduler.new

    scheduler.every '5s' do
      puts "Querying Trello at #{Time.now.to_s}"
      boards.each do |board_with_room|
        board = board_with_room.first
        color = :yellow
        hipchat_room = hipchat[board_with_room.last]
        last_timestamp = timestamps[board.id]
        actions = board.actions(:filter => :all, :since => last_timestamp.iso8601)
        actions.each do |action|
          if last_timestamp < action.date
            board_link = "<a href='https://trello.com/board/#{action.data['board']['id']}'>#{action.data['board']['name']}</a>"
            card_link = "#{board_link} : <a href='https://trello.com/card/#{action.data['board']['id']}/#{action.data['card']['idShort']}'>#{action.data['card']['name']}</a>"
            message = case action.type.to_sym
            when :updateCard
     
              if action.data['listBefore']
                "#{action.member_creator.full_name} ha movido #{card_link} de #{action.data['listBefore']['name']} a #{action.data['listAfter']['name']}"
              elsif action.data['card']['closed'] && !action.data['old']['closed']
                "#{action.member_creator.full_name} ha archivado #{card_link}"
              elsif !action.data['card']['closed'] && action.data['old']['closed']
                "#{action.member_creator.full_name} ha devuelto #{card_link} a la pila"
              elsif action.data['old']['name']
                "#{action.member_creator.full_name} ha renombrado \"#{action.data['old']['name']}\" to #{card_link}"
              end

            when :createCard
              "#{action.member_creator.full_name} ha añadido #{card_link} a #{action.data['list']['name']}"
              color = :red
            when :moveCardToBoard
              "#{action.member_creator.full_name} ha movido #{card_link} de #{action.data['boardSource']['name']} a #{action.data['board']['name']}"
              color = :green
            when :updateCheckItemStateOnCard
              if action.data["checkItem"]["state"] == 'complete'
                "#{action.member_creator.full_name} checkeado \"#{ action.data['checkItem']['name']}\" en #{card_link}"
              else
                "#{action.member_creator.full_name} descheckeado \"#{action.data['checkItem']['name']}\" en #{card_link}"
              end
              color = :purple
            when :commentCard
              "#{action.member_creator.full_name} a comentado en #{card_link}: #{action.data['text']}"
              color = :gray
            when :deleteCard
              "#{action.member_creator.full_name} ha borrado la tarjeta ##{action.data['card']['idShort']}"
              color = :red
             when :addChecklistToCard
               "#{action.member_creator.full_name} añadió un checklist \"#{action.data['checklist']['name']}\" a #{card_link}"
              color = :red
             when :removeChecklistFromCard
               "#{action.member_creator.full_name} quitó un checklist \"#{action.data['checklist']['name']}\" de #{card_link}"
              color = :red
            else
              STDERR.puts action.inspect
              ""
            end

            color = case action.type.to_sym
            when :updateCard
              if action.data['listBefore']
                :green
              elsif action.data['card']['closed'] && !action.data['old']['closed']
                :purple
              elsif !action.data['card']['closed'] && action.data['old']['closed']
                :red
              elsif action.data['old']['name']
                :gray
              end
            when :createCard            
              :red
            when :moveCardToBoard              
              :green
            when :updateCheckItemStateOnCard              
              :purple
            when :commentCard            
              :gray
            when :deleteCard
              :red
             when :addChecklistToCard              
              :red
             when :removeChecklistFromCard               
              :red
            end


            if dedupe.new? message
              puts "Sending: #{message}"
              hipchat_room.send('Trello', message, :color => color)
            else
              puts "Supressing duplicate message: #{message}"
            end
          end
        end
        timestamps[board.id] = actions.first.date if actions.length > 0
      end
    end

    scheduler.join
  end

end

if __FILE__ == $0
  Bot.run
end

