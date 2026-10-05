import { MACRO_STARTERS } from '../macroStarters';
import { INPUT_TYPES, REQUIREMENTS, CATEGORIES } from '../index';
import { MACRO_ACTION_TYPES } from 'dashboard/routes/dashboard/settings/macros/constants';

// What the server accepts: app/models/macro.rb ACTIONS_ATTRS.
const SERVER_ACTIONS = [
  'send_message',
  'add_label',
  'assign_team',
  'assign_agent',
  'mute_conversation',
  'change_status',
  'remove_label',
  'remove_assigned_agent',
  'remove_assigned_team',
  'resolve_conversation',
  'snooze_conversation',
  'change_priority',
  'send_email_transcript',
  'send_attachment',
  'add_private_note',
  'send_webhook_event',
];

const BUILDER_ACTIONS = MACRO_ACTION_TYPES.map(action => action.key);

// Values a wizard would collect: a label input yields a title, a team input an id.
const valuesFor = starter =>
  starter.inputs.reduce((values, input) => {
    if (input.type === INPUT_TYPES.LABEL) values[input.key] = 'escalated';
    if (input.type === INPUT_TYPES.TEAM) values[input.key] = 12;
    return values;
  }, {});

describe('MACRO_STARTERS', () => {
  it('ships starters', () => {
    expect(MACRO_STARTERS.length).toBeGreaterThan(0);
  });

  it.each(MACRO_STARTERS.map(starter => [starter.id, starter]))(
    '%s declares the recipe contract',
    (id, starter) => {
      expect(starter.type).toBe('macro');
      expect(starter.version).toBeGreaterThan(0);
      expect(starter.name).toBe(`RECIPES.MACRO.${id.toUpperCase()}.NAME`);
      expect(starter.description).toBe(
        `RECIPES.MACRO.${id.toUpperCase()}.DESCRIPTION`
      );
      expect(Object.values(CATEGORIES)).toContain(starter.category);
      starter.requires.forEach(key =>
        expect(Object.values(REQUIREMENTS)).toContain(key)
      );
    }
  );

  it.each(MACRO_STARTERS.map(starter => [starter.id, starter]))(
    '%s builds a macro the server would accept',
    (id, starter) => {
      const { actions } = starter.build(valuesFor(starter));

      expect(actions.length).toBeGreaterThan(0);
      actions.forEach(action => {
        expect(SERVER_ACTIONS).toContain(action.action_name);
        // Strong params permit `action_params: []`, which silently drops a hash. Every parameter must be a
        // scalar or the action arrives empty and the macro does nothing.
        expect(Array.isArray(action.action_params)).toBe(true);
        action.action_params.forEach(param => {
          expect(['string', 'number']).toContain(typeof param);
        });
      });
    }
  );

  it.each(MACRO_STARTERS.map(starter => [starter.id, starter]))(
    '%s uses only actions the macro editor can render, so what it makes stays editable',
    (id, starter) => {
      starter.build(valuesFor(starter)).actions.forEach(action => {
        expect(BUILDER_ACTIONS).toContain(action.action_name);
      });
    }
  );

  it.each(MACRO_STARTERS.map(starter => [starter.id, starter]))(
    '%s asks for every account resource it puts in the macro',
    (id, starter) => {
      const declared = starter.inputs.map(input => input.key);
      const requiresTeam = starter
        .build(valuesFor(starter))
        .actions.some(action => action.action_name === 'assign_team');
      const requiresLabel = starter
        .build(valuesFor(starter))
        .actions.some(action => action.action_name === 'add_label');

      if (requiresTeam) {
        expect(declared).toContain('team');
        expect(starter.requires).toContain(REQUIREMENTS.TEAM);
      }
      if (requiresLabel) {
        expect(declared).toContain('label');
        expect(starter.requires).toContain(REQUIREMENTS.LABEL);
      }
    }
  );

  it('never embeds an account id a catalogue cannot know', () => {
    MACRO_STARTERS.forEach(starter => {
      // Built with no values at all: anything that still looks like a resource id was hard-coded.
      const actions = starter.inputs.length
        ? starter.build({})
        : starter.build({});
      JSON.stringify(actions.actions)
        .match(/"\d+"/g)
        ?.forEach(match => {
          throw new Error(`${starter.id} embeds a literal id ${match}`);
        });
    });
  });

  it('includes the one starter an agent can use with nothing set up', () => {
    const takeIt = MACRO_STARTERS.find(
      starter => starter.id === 'take_conversation'
    );

    expect(takeIt.requires).toEqual([]);
    expect(takeIt.inputs).toEqual([]);
    // 'self' is the macro-only sentinel the executor swaps for the clicking agent.
    expect(takeIt.build({}).actions[0]).toEqual({
      action_name: 'assign_agent',
      action_params: ['self'],
    });
  });

  it('claims no Commerce behaviour, because a macro cannot read or change an order', () => {
    MACRO_STARTERS.forEach(starter => {
      starter.build(valuesFor(starter)).actions.forEach(action => {
        expect(action.action_name).not.toMatch(/commerce|order|refund|cancel/);
      });
    });
  });
});
