import importlib.machinery
import importlib.util
import json
import pathlib
import unittest
from unittest import mock

loader=importlib.machinery.SourceFileLoader('signature_network',str(pathlib.Path(__file__).with_name('split-target-docuseal-network')))
spec=importlib.util.spec_from_loader(loader.name,loader)
network=importlib.util.module_from_spec(spec);loader.exec_module(network)


class NetworkTests(unittest.TestCase):
    def test_collision_moves_only_app_to_persistent_address(self):
        attachment={'IPAddress':'172.30.61.3','IPAMConfig':None,'Aliases':['app']}
        replies=[json.dumps([{'Containers':{}}]),json.dumps([{'NetworkSettings':{'Networks':{network.NETWORK:attachment}}}]),'', '']
        with mock.patch.object(network,'run',side_effect=replies) as run:
            network.reconcile()
        self.assertEqual(run.call_args_list[-1].args,('network','connect','--ip','172.30.61.4','--alias','app',network.NETWORK,network.APP))
        self.assertEqual(run.call_args_list[-2].args,('network','disconnect',network.NETWORK,network.APP))

    def test_persistent_assignment_is_idempotent(self):
        attachment={'IPAddress':network.ADDRESS,'IPAMConfig':{'IPv4Address':network.ADDRESS}}
        replies=[json.dumps([{'Containers':{}}]),json.dumps([{'NetworkSettings':{'Networks':{network.NETWORK:attachment}}}])]
        with mock.patch.object(network,'run',side_effect=replies) as run:
            network.reconcile()
        self.assertEqual(run.call_count,2)

    def test_unknown_address_owner_is_preserved(self):
        with mock.patch.object(network,'run',return_value=json.dumps([{'Containers':{'other':{'Name':'unrelated','IPv4Address':'172.30.61.4/24'}}}])) as run:
            with self.assertRaises(RuntimeError): network.reconcile()
        self.assertEqual(run.call_count,1)

    def test_failed_attachment_restores_previous_connectivity(self):
        attachment={'IPAddress':'172.30.61.3','Aliases':[]}
        replies=[json.dumps([{'Containers':{}}]),json.dumps([{'NetworkSettings':{'Networks':{network.NETWORK:attachment}}}]),'',RuntimeError('connect failed'),'']
        with mock.patch.object(network,'run',side_effect=replies) as run:
            with self.assertRaises(RuntimeError):network.reconcile()
        self.assertEqual(run.call_args.args,('network','connect','--ip','172.30.61.3',network.NETWORK,network.APP))


if __name__=='__main__':unittest.main()
