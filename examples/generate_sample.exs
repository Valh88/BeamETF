# generate_sample.exs
#
# Генерирует файл sample.etf с ETF-термами для примера EtfParser.lpr.
#
# Структура данных:
#   {:ok, %{
#     status: :ok,
#     users: [%User{...}, ...],
#     profile: %UserProfile{user: ..., address: %Address{...}, tags: [...], metadata: %{}},
#     total: 3,
#     pi: 3.14159...,
#     greeting: "Привет из Elixir!",
#     ...
#   }}
#
# Запуск: elixir generate_sample.exs

defmodule User do
  defstruct [:id, :name, :email, :active, :score, :role]
end

defmodule Address do
  defstruct [:street, :city, :country]
end

defmodule UserProfile do
  defstruct [:user, :address, :tags, :metadata]
end

defmodule Gen do
  def run do
    users = [
      %User{
        id: 1,
        name: "Alice",
        email: "alice@example.com",
        active: true,
        score: 98.5,
        role: :admin
      },
      %User{
        id: 2,
        name: "Боб",
        email: "bob@example.com",
        active: false,
        score: 75.0,
        role: :user
      },
      %User{
        id: 3,
        name: "Charlie",
        email: "charlie@example.com",
        active: true,
        score: 88.25,
        role: :moderator
      }
    ]

    address = %Address{
      street: "ул. Пушкина, д. 1",
      city: "Москва",
      country: "RU"
    }

    profile = %UserProfile{
      user: hd(users),
      address: address,
      tags: ["pascal", "erlang", "elixir"],
      metadata: %{
        version: 2,
        created_at: "2026-02-24",
        flags: [:beta, :verified]
      }
    }

    payload = %{
      status: :ok,
      users: users,
      profile: profile,
      total: length(users),
      pi: 3.14159265358979,
      greeting: "Привет из Elixir!",
      empty_list: [],
      nil_value: nil,
      bool_true: true,
      bool_false: false
    }

    term = {:ok, payload}

    binary = :erlang.term_to_binary(term)
    output_path = Path.join(__DIR__, "sample.etf")
    File.write!(output_path, binary)

    IO.puts("Written #{byte_size(binary)} bytes → #{output_path}")
    IO.puts("Top-level term: #{inspect(elem(term, 0))}")
    IO.puts("Users count:    #{length(users)}")
    IO.puts("Profile struct: #{inspect(profile.__struct__)}")
  end
end

Gen.run()
