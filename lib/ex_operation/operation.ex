defmodule ExOperation.Operation do
  @moduledoc false

  defstruct multi: nil, context: %{}, params: %{}, after_commit_callbacks: []

  @type t :: %__MODULE__{}
  @callback call(operation :: t()) :: t()
  @callback validate_params(changeset :: Ecto.Changeset.t()) :: Ecto.Changeset.t()
  @optional_callbacks validate_params: 1

  defmacro __using__(opts \\ []) do
    quote do
      @behaviour ExOperation.Operation
      defoverridable ExOperation.Operation

      defmodule Module.concat(__MODULE__, OperationParams) do
        use Params.Schema, Keyword.get(unquote(opts), :params, %{})
      end

      import ExOperation.DSL
    end
  end
end
