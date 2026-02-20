class GithubEventsController < ApplicationController
  def index
    @events = GithubEvent.recent.page(params[:page]).per(20)
  end

  def fetch
    result = GithubEventsFetcher.fetch_and_store(per_page: 30)
    
    if result[:success]
      redirect_to github_events_path, notice: "Fetched #{result[:count]} events"
    else
      redirect_to github_events_path, alert: "Error: #{result[:error]}"
    end
  end

  # API endpoint to get events as JSON
  def api_index
    @events = GithubEvent.recent.limit(50)
    render json: @events
  end

  # def show
  #   @event = GithubEvent.find(params[:id])
  # end
end