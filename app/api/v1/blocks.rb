module Api
  module V1

    class Blocks < Grape::API
      resource :blocks do
        get ':id' do
          block = Block.find(params["id"])
          return forbidden! unless block.visible_to_user?(current_person) || block.allow_edit?(current_person)
          block.api_content_params = params.except("id")
          present block, :with => Entities::Block, display_api_content: true, current_person: current_person
        end

        post ':id' do
          block = Block.find(params["id"])
          return forbidden! unless block.allow_edit?(current_person)
          block.update_attributes!(asset_with_images(params[:block]))
          present block, :with => Entities::Block, display_api_content: true, current_person: current_person
        end
      end
    end

  end
end
