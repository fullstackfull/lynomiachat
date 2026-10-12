import { readFileSync } from 'node:fs';
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SidebarSubGroup from '../SidebarSubGroup.vue';
import { provideSidebarContext } from '../provider';
import customRoles from 'dashboard/routes/dashboard/settings/customRoles/customRole.routes';

// The route module pulls its page components in, and those reach the whole route graph, which imports this
// module back. Stubbing the two components keeps the import to the declaration this file is about.
vi.mock('dashboard/routes/dashboard/settings/SettingsWrapper.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('dashboard/routes/dashboard/settings/customRoles/Index.vue', () => ({
  default: { template: '<div />' },
}));

// The Custom Roles settings page had no entry point anywhere in the dashboard: `custom_roles_list` was
// reachable only by typing its URL. This covers the entry that fixes that, and the two declarations that make
// it safe to show -- because the sidebar does not carry its own guard, it reads the target route's meta
// (sidebar/provider.js `isAllowed`), so the route's meta IS the gate for both the nav item and the direct URL.
const ROUTE_NAME = 'custom_roles_list';

const route = customRoles.routes[0].children.find(
  child => child.name === ROUTE_NAME
);

// What `usePolicy().shouldShow` decides on a branded installation such as Lynomia: the account feature flag
// and the member's permissions, and nothing else (composables/usePolicy.js). Driven from these two refs so an
// example can change either and watch the entry appear or vanish.
const accountFeatures = ref([]);
const userPermissions = ref([]);

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(1),
}));

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    shouldShow: (featureFlag, permissions) => {
      if (
        permissions?.length &&
        !permissions.some(p => userPermissions.value.includes(p))
      ) {
        return false;
      }
      return !featureFlag || accountFeatures.value.includes(featureFlag);
    },
  }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({
    // The real router resolves a nav target to its route definition, meta included. That is the only thing
    // `isAllowed` uses, so returning this route's own meta is the honest stub.
    resolve: () => ({ path: '/settings/custom-roles/list', meta: route.meta }),
    getRoutes: () => [],
  }),
}));

const mountPeopleGroup = () =>
  mount(
    {
      components: { SidebarSubGroup },
      setup() {
        provideSidebarContext({});
      },
      template: '<SidebarSubGroup v-bind="$attrs" />',
    },
    {
      attrs: {
        name: 'Settings People',
        label: 'People',
        icon: 'i-lucide-users-round',
        collapsible: false,
        isExpanded: true,
        children: [
          {
            name: 'Settings Custom Roles',
            label: 'Custom Roles',
            icon: 'i-lucide-shield-check',
            to: { name: ROUTE_NAME },
          },
        ],
      },
      global: {
        stubs: {
          SidebarGroupLeaf: {
            props: { label: { type: String, required: true } },
            template: '<li class="sidebar-leaf">{{ label }}</li>',
          },
        },
      },
    }
  );

describe('the Custom Roles settings entry', () => {
  beforeEach(() => {
    accountFeatures.value = [];
    userPermissions.value = [];
  });

  describe('the route it points at', () => {
    it('exists', () => {
      expect(route).toBeTruthy();
    });

    // Both halves matter: the flag keeps the entry away from an account that has not bought the capability,
    // and the permission keeps it away from every member who is not an administrator. The server refuses on
    // both counts too (custom/app/controllers/api/v1/accounts/custom_roles_controller.rb), which is the
    // authorization; this is what stops the dashboard offering a dead end.
    it('declares the custom_roles feature flag and administrator permission', () => {
      expect(route.meta.featureFlag).toBe('custom_roles');
      expect(route.meta.permissions).toEqual(['administrator']);
    });
  });

  // The regression this file exists for. Asserted against the source because mounting Sidebar.vue means
  // standing up the whole dashboard store, and what went wrong was not a rendering bug -- the entry was simply
  // not in the menu. The examples below then cover what happens once it is.
  it('is present in the sidebar menu, under the People section of Settings', () => {
    const sidebar = readFileSync(
      'app/javascript/dashboard/components-next/sidebar/Sidebar.vue',
      'utf8'
    );

    expect(sidebar).toContain(`accountScopedRoute('${ROUTE_NAME}')`);
    expect(sidebar).toContain("label: t('SIDEBAR.CUSTOM_ROLES')");
  });

  describe('visibility in the sidebar', () => {
    it('shows for an administrator of an entitled account', () => {
      accountFeatures.value = ['custom_roles'];
      userPermissions.value = ['administrator'];

      expect(mountPeopleGroup().find('.sidebar-leaf').exists()).toBe(true);
    });

    it('hides when the account does not have the capability', () => {
      accountFeatures.value = [];
      userPermissions.value = ['administrator'];

      expect(mountPeopleGroup().find('.sidebar-leaf').exists()).toBe(false);
    });

    it('hides from an agent, however the account is entitled', () => {
      accountFeatures.value = ['custom_roles'];
      userPermissions.value = ['agent'];

      expect(mountPeopleGroup().find('.sidebar-leaf').exists()).toBe(false);
    });

    it('hides from a custom-role holder, who may hold every capability and still not administer sets', () => {
      accountFeatures.value = ['custom_roles'];
      userPermissions.value = [
        'custom_role',
        'conversation_manage',
        'report_manage',
      ];

      expect(mountPeopleGroup().find('.sidebar-leaf').exists()).toBe(false);
    });
  });
});
