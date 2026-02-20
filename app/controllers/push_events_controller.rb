class PushEventsController < ApplicationController
  def index
    @push_events = PushEvent.includes(:github_event).page(params[:page]).per(20)
  end

  def show
    @push_event = PushEvent.find(params[:id])
    @github_event = @push_event.github_event
  end
end