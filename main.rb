require "telegram/bot"

class TicTacToeBot
  def initialize(token)
    @token = token
    @board = Array.new(9, " ")
  end

  def start
    Telegram::Bot::Client.run(@token) do |bot|
      bot.listen do |message|
        case message
        when Telegram::Bot::Types::Message
          handle_text_message(bot, message)
        when Telegram::Bot::Types::CallbackQuery
          handle_callback_query(bot, message)
        end
      end
    end
  end

  def handle_text_message(bot, message)
    case message.text
    when "/start"
      send_instructions(bot, message.chat.id)
    when "/play"
      play_game(bot, message.chat.id, message.from.id)
    when "/reset"
      reset_game(bot, message.chat.id)
    end
  end

  def handle_callback_query(bot, query)
    case query.data
    when "/start"
      send_instructions(bot, query.message.chat.id)
    when "/play"
      play_game(bot, query.message.chat.id, query.from.id)
    when "/reset"
      reset_game(bot, query.message.chat.id)
    end
  end

  private

  def send_instructions(bot, chat_id)
    message = <<~INSTRUCTIONS
      Welcome to Tic Tac Toe Bot! Here are the instructions:
      1. Type /play to start a new game.
      2. Choose "X" or "O" when prompted.
      3. Use numbers 1-9 to make a move on the board.
      4. Type /reset to reset the game.
    INSTRUCTIONS

    bot.api.send_message(chat_id: chat_id, text: message)
  end

  def ask_user_symbol(bot, chat_id, user_id)
    buttons = [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌", callback_data: "X"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "⭕", callback_data: "O")
    ]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [buttons])

    bot.api.send_message(chat_id: chat_id, text: "Choose your game", reply_markup: markup)

    bot.listen do |update|
      if update.is_a?(Telegram::Bot::Types::CallbackQuery)
        choice = update.data
        return choice if ["X", "O"].include?(choice)
      end
    end
  end

  def play_game(bot, chat_id, user_id)
    user_choice = ask_user_symbol(bot, chat_id, user_id)

    computer_choice = (user_choice == "X" ? "O" : "X")
    bot.api.send_message(chat_id: chat_id, text: "You chose #{user_choice}. I'll be #{computer_choice}")

    show_board(bot, chat_id)
    play_turns(bot, chat_id, user_id, user_choice, computer_choice)
  end

  def show_board(bot, chat_id)
    board_display = <<~BOARD
    +-----+-----+-----+
    |  #{display_cell(1)}  |  #{display_cell(2)}  |  #{display_cell(3)}  |
    +-----+-----+-----+
    |  #{display_cell(4)}  |  #{display_cell(5)} |  #{display_cell(6)}  |
    +-----+-----+-----+
    |  #{display_cell(7)}  |  #{display_cell(8)}  |  #{display_cell(9)}  |
    +-----+-----+-----+
    BOARD

    bot.api.send_message(chat_id: chat_id, text: board_display)
  end

  def play_turns(bot, chat_id, user_id, user_choice, computer_choice)
    current_player = user_id
    game_over = false

    bot.api.send_message(chat_id: chat_id, text: "Let's start the game!")

    until game_over
      show_board(bot, chat_id)

      if current_player == user_id
        make_user_move(bot, chat_id, user_id, user_choice)
      else
        bot.api.send_message(chat_id: chat_id, text: "My turn!")
        make_computer_move(computer_choice, user_choice)
      end

      game_over = check_game_status(bot, chat_id, user_choice, computer_choice)

      current_player = (current_player == user_id) ? bot.api.get_me["result"]["id"] : user_id
    end

    bot.api.send_message(chat_id: chat_id, text: "Game over! Type /play to start a new game.")
  end

  def make_user_move(bot, chat_id, user_id, user_choice)
    buttons = (1..9).map do |i|
      Telegram::Bot::Types::InlineKeyboardButton.new(text: i.to_s, callback_data: i.to_s)
    end

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons.each_slice(3).to_a)

    bot.api.send_message(chat_id: chat_id, text: "Your turn! Choose a number (1-9):", reply_markup: markup)

    bot.listen do |message|
      if message.is_a?(Telegram::Bot::Types::CallbackQuery)
        process_user_input(bot, chat_id, user_id, user_choice, message)
        break
      end
    end
  end

  def process_user_input(bot, chat_id, user_id, user_choice, callback_query)
    move = callback_query.data.to_i
    if (1..9).include?(move) && @board[move - 1] == " "
      @board[move - 1] = user_choice
    else
      bot.api.send_message(chat_id: chat_id, text: "Invalid move. Please choose an empty cell (1-9) or type /reset:")
      make_user_move(bot, chat_id, user_id, user_choice)
    end
  end

  def make_computer_move(computer_choice, user_choice)
    best_score = -Float::INFINITY
    best_move = nil

    empty_cells = @board.each_index.select { |i| @board[i] == " " }

    if !empty_cells.empty?
      empty_cells.each do |move|
        @board[move] = computer_choice

        # Check if the computer can win
        if check_winner(computer_choice)
          score = 100
        else
          # Block the opponent's winning move
          if check_winner(user_choice)
            score = -100
          else
            # Use the minimax or heuristic evaluation
            score = minimax(0, false, -Float::INFINITY, Float::INFINITY, depth_limit: 3)
            score = heuristic_evaluation if score.nil? # Use heuristic evaluation if minimax returns nil
          end
        end

        @board[move] = " "  # Undo the move

        if score > best_score
          best_score = score
          best_move = move
        end
      end
    end

    @board[best_move] = computer_choice if best_move
  end

  def minimax(depth, is_maximizing, alpha = -Float::INFINITY, beta = Float::INFINITY, depth_limit: nil)
    scores = {
      "X" => 1,
      "O" => -1,
      " " => 0
    }

    winner = check_winner("X") || check_winner("O")
    return scores[winner] if winner

    return 0 if @board.none?(" ")

    if is_maximizing
      max_eval = -Float::INFINITY
      empty_cells = @board.each_index.select { |i| @board[i] == " " }.shuffle
      empty_cells.each do |i|
        @board[i] = "X"
        eval = minimax(depth + 1, false, alpha, beta)
        @board[i] = " "
        max_eval = [max_eval, eval || 0].max
        alpha = [alpha, max_eval].max
        break if beta <= alpha
      end
      return max_eval
    else
      min_eval = Float::INFINITY
      @board.each_index do |i|
        if @board[i] == " "
          @board[i] = "O"
          eval = minimax(depth + 1, true, alpha, beta)
          @board[i] = " "
          min_eval = [min_eval, eval || 0].min
          beta = [beta, min_eval].min
          break if beta <= alpha
        end
      end
      return min_eval
    end
  end

  def heuristic_evaluation
    total_score = 0

    winning_combinations = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], # Rows
      [0, 3, 6], [1, 4, 7], [2, 5, 8], # Columns
      [0, 4, 8], [2, 4, 6]             # Diagonals
    ]

    winning_combinations.each do |combo|
      combo_values = combo.map { |index| @board[index] }
      user_count = combo_values.count("X")
      opponent_count = combo_values.count("O")

      # Block the user from winning
      if user_count == 2 && combo_values.include?(" ")
        total_score += 100
      end

      # Favor blocking opponent
      total_score += 50 if opponent_count == 2 && combo_values.include?(" ")

      # Favor center and corner moves
      total_score += 10 if [1, 3, 5, 7].include?(combo[1])
      total_score += 5 if [0, 2, 6, 8].include?(combo[1])
    end

    total_score
  end


  def opponent(player)
    player == "X" ? "O" : "X"
  end


  def check_game_status(bot, chat_id, user_choice, computer_choice)
    result_message = nil

    if check_winner(user_choice)
      result_message = "Congratulations! You win!"
      show_board(bot, chat_id)
    elsif check_winner(computer_choice)
      result_message = "I win! Better luck next time."
      show_board(bot, chat_id)
    elsif board_full?
      result_message = "It's a draw! The board is full."
      show_board(bot, chat_id)
    end

    if result_message
      bot.api.send_message(chat_id: chat_id, text: result_message)
      clear_board(bot, chat_id)
      return true
    else
      return false
    end
  end

  def check_winner(player)
    # Check rows, columns, and diagonals for a win
    winning_combinations = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8], # Rows
      [0, 3, 6], [1, 4, 7], [2, 5, 8], # Columns
      [0, 4, 8], [2, 4, 6]             # Diagonals
    ]

    winning_combinations.each do |combo|
      line = combo.map { |index| @board[index] }.join(" ")
      return true if combo.all? { |index| @board[index] == player }
    end

    false
  end

  def board_full?
    # Check if the board is full (no empty cells)
    !@board.include?(" ")
  end

  def reset_game(bot, chat_id)
    @board = Array.new(9, " ")
    bot.api.send_message(chat_id: chat_id, text: "Game has been reset. Type /play to start a new game.")
  end

  def clear_board(bot, chat_id)
    @board = Array.new(9, " ")
  end

  def display_cell(index)
    cell_value = @board[index - 1]
    case cell_value
    when "X"
      "❌" # Emoji for "X"
    when "O"
      "⭕" # Emoji for "O"
    else
      "⬜️ " # Emoji for empty cell
    end
  end
end

bot_token = "6841577744:AAG0IqEzf73zCRThzzHggszZMOOd_ASMyQ0"
TicTacToeBot.new(bot_token).start
