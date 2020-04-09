# (c) goodprogrammer.ru

require 'rails_helper'
require 'support/my_spec_helper' # наш собственный класс с вспомогательными методами

# Тестовый сценарий для модели Игры
# В идеале - все методы должны быть покрыты тестами,
# в этом классе содержится ключевая логика игры и значит работы сайта.
RSpec.describe Game, type: :model do
  # пользователь для создания игр
  let(:user) { FactoryGirl.create(:user) }

  # игра с прописанными игровыми вопросами
  let(:game_w_questions) { FactoryGirl.create(:game_with_questions, user: user) }

  # Группа тестов на работу фабрики создания новых игр
  context 'Game Factory' do
    it 'Game.create_game! new correct game' do
      # генерим 60 вопросов с 4х запасом по полю level,
      # чтобы проверить работу RANDOM при создании игры
      generate_questions(60)

      game = nil
      # создaли игру, обернули в блок, на который накладываем проверки
      expect {
        game = Game.create_game_for_user!(user)
      }.to change(Game, :count).by(1).and(# проверка: Game.count изменился на 1 (создали в базе 1 игру)
          change(GameQuestion, :count).by(15).and(# GameQuestion.count +15
              change(Question, :count).by(0) # Game.count не должен измениться
          )
      )
      # проверяем статус и поля
      expect(game.user).to eq(user)
      expect(game.status).to eq(:in_progress)
      # проверяем корректность массива игровых вопросов
      expect(game.game_questions.size).to eq(15)
      expect(game.game_questions.map(&:level)).to eq (0..14).to_a
    end

    it 'take_money! finishes the game' do
      # берем игру и отвечаем на текущий вопрос
      q = game_w_questions.current_game_question
      game_w_questions.answer_current_question!(q.correct_answer_key)

      # взяли деньги
      game_w_questions.take_money!

      prize = game_w_questions.prize
      expect(prize).to be > 0

      # проверяем что закончилась игра и пришли деньги игроку
      expect(game_w_questions.status).to eq :money
      expect(game_w_questions.finished?).to be_truthy
      expect(user.balance).to eq prize
    end
  end

  # тесты на основную игровую логику
  context 'game mechanics' do

    # правильный ответ должен продолжать игру
    it 'answer correct continues game' do
      # текущий уровень игры и статус
      level = game_w_questions.current_level
      q = game_w_questions.current_game_question
      expect(game_w_questions.status).to eq(:in_progress)

      game_w_questions.answer_current_question!(q.correct_answer_key)

      # перешли на след. уровень
      expect(game_w_questions.current_level).to eq(level + 1)
      # ранее текущий вопрос стал предыдущим
      expect(game_w_questions.previous_game_question).to eq(q)
      expect(game_w_questions.current_game_question).not_to eq(q)
      # игра продолжается
      expect(game_w_questions.status).to eq(:in_progress)
      expect(game_w_questions.finished?).to be_falsey
    end
  end

  # группа тестов на проверку статуса игры
  context '.status' do
    # перед каждым тестом "завершаем игру"
    before(:each) do
      game_w_questions.finished_at = Time.now
      expect(game_w_questions.finished?).to be_truthy
    end

    it ':won' do
      game_w_questions.current_level = Question::QUESTION_LEVELS.max + 1
      expect(game_w_questions.status).to eq(:won)
    end

    it ':fail' do
      game_w_questions.is_failed = true
      expect(game_w_questions.status).to eq(:fail)
    end

    it ':timeout' do
      game_w_questions.created_at = 1.hour.ago
      game_w_questions.is_failed = true
      expect(game_w_questions.status).to eq(:timeout)
    end

    it ':money' do
      expect(game_w_questions.status).to eq(:money)
    end
  end
end

describe '#previous_level' do
  let(:user) { FactoryGirl.create(:user) }
  let(:game_w_questions) { FactoryGirl.create(:game_with_questions, user: user) }

  it 'returns the correct value of the previous level' do
    expect(game_w_questions.previous_level).to eq(game_w_questions.current_level - 1)
  end
end

describe 'current_game_question' do
  let(:user) { FactoryGirl.create(:user) }
  let(:game_w_questions) { FactoryGirl.create(:game_with_questions, user: user) }

  it 'returns the correct value of the current level' do
    expect(game_w_questions.current_game_question).to eq(game_w_questions.game_questions[0])
  end
end

# Рассмотрите случаи, когда ответ правильный,
# неправильный,
# последний (на миллион)
# и когда ответ дан после истечения времени
describe '#answer_current_question!' do
  # пользователь для создания игр
  let(:user) { FactoryGirl.create(:user) }
  # игра с прописанными игровыми вопросами
  let(:game_w_questions) { FactoryGirl.create(:game_with_questions, user: user) }

  context 'possible options for the method' do

    it 'correct answer' do
      q = game_w_questions.current_game_question
      level = game_w_questions.current_level

      expect(game_w_questions.answer_current_question!(q.correct_answer_key)).to eq(true)
      expect(game_w_questions.current_level).to eq(level += 1)
      expect(game_w_questions.finished?).to eq(false)

      if game_w_questions.finished?
        expect(fire_proof_prize(level + 12)).to eq(32000)
        expect(fire_proof_prize(level)).to eq(0)
      end
    end

    it 'not correct answer' do
      level = game_w_questions.current_level

      expect(game_w_questions.answer_current_question!('a')).to eq(false)
      expect(game_w_questions.finished?).to eq(true)
      expect(game_w_questions.current_level).not_to eq(level + 1)
    end

    it 'last question' do
      current_level_max = Question::QUESTION_LEVELS.max
      level = game_w_questions.current_level

      if game_w_questions.current_level == current_level_max
        expect(game_w_questions.answer_current_question!).to
        eq(
                level + 1 &&
                finish_game!(PRIZES[current_level_max]) &&
                game_w_questions.finished? == true
        )

        expect(fire_proof_prize(level)).to eq(1_000_000)
      end
    end

    it 'time to answer expired' do
      q = game_w_questions.current_game_question
      level = game_w_questions.current_level

      if game_w_questions.time_out!
        expect(game_w_questions.answer_current_question!(q.correct_answer_key)).to eq(false)
        expect(game_w_questions.current_level).not_to eq(level + 1)
        expect(fire_proof_prize(level + 5)).to eq(1_000)
      end
    end
  end
end
