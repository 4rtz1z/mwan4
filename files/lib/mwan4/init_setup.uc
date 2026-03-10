'use strict';
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 MOSSDeF, Stan Grishin (stangri@melmac.ca).
// Based on original mwan3 by Florian Eckert <fe@dev.tdt.de>
//
// Called by init.d/mwan4 start_service to set up nftables, routes and rules.
// Procd instance management (trackers, rtmon) stays in shell.

import m from 'mwan4';

m.set_scriptname('mwan4-init');
m.init();

m.update_iface_to_table();
m.set_general_rules();

// Initialize enabled interfaces directly during startup. Relying on the
// hotplug helper here proved too fragile and left fwmark policy rules absent.
m.uci_foreach('interface', function(s) {
	let iface = s['.name'];
	if (!m.uci_bool(s.enabled))
		return;

	let id = m.get_iface_id(iface);
	if (id) {
		let mark = m.get_iface_mark(iface);
		let lookup_cmd = sprintf('ip -4 rule add pref %d fwmark %s/%s lookup %d', id + 2000, mark, m.mmx_mask, id);
		let unreachable_cmd = sprintf('ip -4 rule add pref %d fwmark %s/%s unreachable', id + 3000, mark, m.mmx_mask);
		m.LOG('notice', sprintf("startup adding lookup rule for '%s': %s", iface, lookup_cmd));
		system(lookup_cmd + ' >/dev/null 2>&1');
		m.LOG('notice', sprintf("startup adding unreachable rule for '%s': %s", iface, unreachable_cmd));
		system(unreachable_cmd + ' >/dev/null 2>&1');
	}
	m.create_iface_route(iface);

	let initial_state = m.uci_get(iface, 'initial_state') || 'online';
	m.set_iface_hotplug_state(iface, initial_state == 'offline' ? 'offline' : 'online');
});

// Generate dynamic file (base structure + interfaces + strategies)
m.rebuild_dynamic();

// Generate rules file (sets + user rules)
m.nft_file('create', 'rules');
m.set_dynamic_nftset();
m.set_connected_ipv4();
m.set_connected_ipv6();
m.set_custom_nftset();
m.set_user_rules();

// Validate combined and install
m.nft_file('install', 'all');
m.fw4_reload();
