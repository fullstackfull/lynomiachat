import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import CampaignsAPI from '../../api/campaigns';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { CAMPAIGNS_EVENTS } from '../../helper/AnalyticsHelper/events';
import { CAMPAIGN_TYPES } from 'shared/constants/campaign';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    // Whether the LAST fetch failed. Without it an empty `records` means two different things --
    // "this account has no campaigns" and "we could not find out" -- and the page drew the first
    // for both, telling people they had none when the request had actually failed.
    hasError: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getCampaigns:
    _state =>
    (campaignType, inboxChannelTypes = null) => {
      let filteredRecords = _state.records.filter(
        record => record.campaign_type === campaignType
      );

      if (inboxChannelTypes && Array.isArray(inboxChannelTypes)) {
        filteredRecords = filteredRecords.filter(record => {
          return (
            record.inbox &&
            inboxChannelTypes.includes(record.inbox.channel_type)
          );
        });
      }

      return filteredRecords.sort((a1, a2) => a1.id - a2.id);
    },
  getSMSCampaigns: (_state, _getters) => {
    const smsChannelTypes = [INBOX_TYPES.SMS, INBOX_TYPES.TWILIO];
    return _getters.getCampaigns(CAMPAIGN_TYPES.ONE_OFF, smsChannelTypes);
  },
  getWhatsAppCampaigns: (_state, _getters) => {
    const whatsappChannelTypes = [INBOX_TYPES.WHATSAPP];
    return _getters.getCampaigns(CAMPAIGN_TYPES.ONE_OFF, whatsappChannelTypes);
  },
  getLiveChatCampaigns: (_state, _getters) => {
    const liveChatChannelTypes = [INBOX_TYPES.WEB];
    return _getters.getCampaigns(CAMPAIGN_TYPES.ONGOING, liveChatChannelTypes);
  },
  getAllCampaigns: _state => {
    return _state.records;
  },
};

export const actions = {
  get: async function getCampaigns({ commit }) {
    commit(types.SET_CAMPAIGN_UI_FLAG, { isFetching: true, hasError: false });
    try {
      const response = await CampaignsAPI.get();
      commit(types.SET_CAMPAIGNS, response.data);
    } catch (error) {
      // Recorded rather than ignored. The list has no other way to tell the difference between an
      // account with no campaigns and a request that never came back.
      commit(types.SET_CAMPAIGN_UI_FLAG, { hasError: true });
    } finally {
      commit(types.SET_CAMPAIGN_UI_FLAG, { isFetching: false });
    }
  },
  create: async function createCampaign({ commit }, campaignObj) {
    commit(types.SET_CAMPAIGN_UI_FLAG, { isCreating: true });
    try {
      const response = await CampaignsAPI.create(campaignObj);
      commit(types.ADD_CAMPAIGN, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CAMPAIGN_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...updateObj }) => {
    commit(types.SET_CAMPAIGN_UI_FLAG, { isUpdating: true });
    try {
      const response = await CampaignsAPI.update(id, updateObj);
      AnalyticsHelper.track(CAMPAIGNS_EVENTS.UPDATE_CAMPAIGN);
      commit(types.EDIT_CAMPAIGN, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CAMPAIGN_UI_FLAG, { isUpdating: false });
    }
  },
  delete: async ({ commit }, id) => {
    commit(types.SET_CAMPAIGN_UI_FLAG, { isDeleting: true });
    try {
      await CampaignsAPI.delete(id);
      AnalyticsHelper.track(CAMPAIGNS_EVENTS.DELETE_CAMPAIGN);
      commit(types.DELETE_CAMPAIGN, id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_CAMPAIGN_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_CAMPAIGN_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.ADD_CAMPAIGN]: MutationHelpers.create,
  [types.SET_CAMPAIGNS]: MutationHelpers.set,
  [types.EDIT_CAMPAIGN]: MutationHelpers.update,
  [types.DELETE_CAMPAIGN]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
