defmodule LiveAdmin.Components.Container.Form do
  use Phoenix.LiveComponent
  use Phoenix.HTML

  import LiveAdmin.ErrorHelpers
  import LiveAdmin, only: [associated_resource: 4, route_with_params: 2, trans: 1]

  alias __MODULE__.{ArrayInput, Embed, MapInput, SearchSelect}
  alias LiveAdmin.Resource

  @supported_primitive_types [
    :string,
    :boolean,
    :date,
    :integer,
    :naive_datetime,
    :utc_datetime,
    :id,
    :binary_id,
    :float
  ]

  @impl true
  def update(assigns = %{record: record}, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:enabled, false)
      |> assign(:changeset, Resource.change(assigns.resource, record))

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:enabled, false)
      |> assign(:changeset, Resource.change(assigns.resource))

    {:ok, socket}
  end

  @impl true
  def render(assigns = %{record: nil}) do
    ~H"""
    <div><%= trans("No record found") %></div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="form-page" phx-hook="FormPage">
      <.form
        :let={f}
        for={@changeset}
        as={:params}
        phx-change="validate"
        phx-submit={@action}
        phx-target={@myself}
        class="resource__form"
      >
        <%= for {field, type, opts} <- Resource.fields(@resource) do %>
          <.field
            field={field}
            type={type}
            form={f}
            immutable={Keyword.get(opts, :immutable, false)}
            resource={@resource}
            resources={@resources}
            session={@session}
            prefix={@prefix}
            repo={@repo}
          />
        <% end %>
        <div class="form__actions">
          <%= submit(trans("Save"),
            class: "resource__action#{if !@enabled, do: "--disabled", else: "--btn"}",
            disabled: !@enabled
          ) %>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event(
        "validate",
        %{"field" => field, "value" => value},
        socket = %{assigns: %{resource: resource, changeset: changeset, session: session}}
      ) do
    changeset = validate(resource, changeset, Map.put(changeset.params, field, value), session)

    {:noreply,
     assign(socket,
       changeset: changeset,
       enabled: enabled?(changeset, socket.assigns.action, resource)
     )}
  end

  @impl true
  def handle_event(
        "validate",
        %{"params" => params},
        socket = %{assigns: %{resource: resource, changeset: changeset, session: session}}
      ) do
    changeset = validate(resource, changeset, params, session)

    {:noreply,
     assign(socket,
       changeset: changeset,
       enabled: enabled?(changeset, socket.assigns.action, resource)
     )}
  end

  @impl true
  def handle_event(
        "create",
        %{"params" => params},
        %{assigns: %{resource: resource, session: session, repo: repo}} = socket
      ) do
    socket =
      case Resource.create(resource, params, session, repo) do
        {:ok, _} ->
          socket
          |> put_flash(:info, trans("Record successfully added"))
          |> push_redirect(
            to: route_with_params(socket.assigns, params: [prefix: socket.assigns.prefix])
          )

        {:error, changeset} ->
          assign(socket, changeset: changeset)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "update",
        %{"params" => params},
        %{assigns: %{resource: resource, session: session, record: record}} = socket
      ) do
    socket =
      Resource.update(record, resource, params, session)
      |> case do
        {:ok, _} ->
          socket
          |> put_flash(:info, trans("Record successfully updated"))
          |> push_redirect(to: route_with_params(socket.assigns, segments: [record]))

        {:error, changeset} ->
          assign(socket, changeset: changeset)
      end

    {:noreply, socket}
  end

  def field(assigns) do
    ~H"""
    <div class={"field__group#{if @immutable, do: "--disabled"} field__#{field_class(@type)}"}>
      <%= label(@form, @field, @field |> humanize() |> trans(), class: "field__label") %>
      <%= if supported_type?(@type) do %>
        <.input
          form={@form}
          type={@type}
          field={@field}
          disabled={@immutable}
          resource={@resource}
          resources={@resources}
          session={@session}
          prefix={@prefix}
          repo={@repo}
        />
      <% else %>
        <%= textarea(@form, @field,
          rows: 1,
          disabled: true,
          value: @form |> input_value(@field) |> inspect()
        ) %>
      <% end %>
      <%= error_tag(@form, @field) %>
    </div>
    """
  end

  defp input(assigns = %{type: {_, Ecto.Embedded, _}}) do
    ~H"""
    <.live_component
      module={Embed}
      id={input_id(@form, @field)}
      type={@type}
      disabled={@disabled}
      form={@form}
      field={@field}
      resource={@resource}
      resources={@resource}
      session={@session}
      prefix={@prefix}
      repo={@repo}
    />
    """
  end

  defp input(assigns = %{type: id}) when id in [:id, :binary_id] do
    assigns =
      assign(
        assigns,
        :associated_resource,
        associated_resource(
          assigns.resource.__live_admin_config__(:schema),
          assigns.field,
          assigns.resources,
          :resource
        )
      )

    ~H"""
    <%= if @associated_resource do %>
      <%= unless @form.data |> Ecto.primary_key() |> Keyword.keys() |> Enum.member?(@field) do %>
        <.live_component
          module={SearchSelect}
          id={input_id(@form, @field)}
          form={@form}
          field={@field}
          disabled={@disabled}
          resource={@associated_resource}
          session={@session}
          prefix={@prefix}
          repo={@repo}
        />
      <% else %>
        <div class="form__number">
          <%= number_input(@form, @field, disabled: @disabled) %>
        </div>
      <% end %>
    <% else %>
      <%= textarea(@form, @field, rows: 1, disabled: @disabled) %>
    <% end %>
    """
  end

  defp input(assigns = %{type: {:array, :string}}) do
    ~H"""
    <.live_component
      module={ArrayInput}
      id={input_id(@form, @field)}
      form={@form}
      field={@field}
      disabled={@disabled}
    />
    """
  end

  defp input(assigns = %{type: :map}) do
    ~H"""
    <.live_component
      module={MapInput}
      id={input_id(@form, @field)}
      form={@form}
      field={@field}
      disabled={@disabled}
    />
    """
  end

  defp input(assigns = %{type: :string}) do
    ~H"""
    <%= textarea(@form, @field, rows: 1, disabled: @disabled, phx_debounce: 200) %>
    """
  end

  defp input(assigns = %{type: :boolean}) do
    ~H"""
    <div class="form__checkbox">
      <%= checkbox(@form, @field, disabled: @disabled) %>
    </div>
    """
  end

  defp input(assigns = %{type: :date}) do
    ~H"""
    <%= date_input(@form, @field, disabled: @disabled) %>
    """
  end

  defp input(assigns = %{type: number}) when number in [:integer, :id] do
    ~H"""
    <div class="form__number">
      <%= number_input(@form, @field, disabled: @disabled, phx_debounce: 200) %>
    </div>
    """
  end

  defp input(assigns = %{type: :float}) do
    ~H"""
    <div class="form__number">
      <%= number_input(@form, @field, disabled: @disabled, step: "any", phx_debounce: 200) %>
    </div>
    """
  end

  defp input(assigns = %{type: type}) when type in [:naive_datetime, :utc_datetime] do
    ~H"""
    <div class="form__time">
      <%= datetime_local_input(@form, @field, disabled: @disabled) %>
    </div>
    """
  end

  defp input(assigns = %{type: {_, Ecto.Enum, %{mappings: mappings}}}) do
    assigns = assign(assigns, :mappings, mappings)

    ~H"""
    <%= select(@form, @field, [nil | Keyword.keys(@mappings)], disabled: @disabled) %>
    """
  end

  defp input(assigns = %{type: {:array, {_, Ecto.Enum, %{mappings: mappings}}}}) do
    assigns = assign(assigns, :mappings, mappings)

    ~H"""
    <div class="checkbox__group">
      <%= hidden_input(@form, @field, name: input_name(@form, @field) <> "[]", value: nil) %>
      <%= for option <- Keyword.keys(@mappings) do %>
        <%= checkbox(@form, @field,
          name: input_name(@form, @field) <> "[]",
          checked_value: option,
          value: @form |> input_value(@field) |> Kernel.||([]) |> Enum.find(&(&1 == option)),
          unchecked_value: "",
          hidden_input: false,
          disabled: @disabled,
          id: input_id(@form, @field) <> to_string(option)
        ) %>
        <label for={input_id(@form, @field) <> to_string(option)}>
          <%= trans(to_string(option)) %>
        </label>
      <% end %>
    </div>
    """
  end

  defp validate(resource, changeset, params, session) do
    resource
    |> Resource.change(changeset.data, params)
    |> Resource.validate(resource, session)
  end

  defp field_class(type) when type in @supported_primitive_types, do: to_string(type)
  defp field_class(:map), do: "map"
  defp field_class({:array, _}), do: "array"
  defp field_class({_, Ecto.Embedded, _}), do: "embed"
  defp field_class({_, Ecto.Enum, _}), do: "enum"
  defp field_class(_), do: "other"

  defp supported_type?(type) when type in @supported_primitive_types, do: true
  defp supported_type?(:map), do: true
  defp supported_type?({:array, _}), do: true
  defp supported_type?({_, Ecto.Embedded, _}), do: true
  defp supported_type?({_, Ecto.Enum, _}), do: true
  defp supported_type?(_), do: false

  def enabled?(changeset, action, resource) do
    resource.__live_admin_config__(:"#{action}_with") != false && Enum.empty?(changeset.errors)
  end
end
