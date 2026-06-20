import importlib.util
from pathlib import Path
import sys
import unittest


SCRIPT = Path(__file__).parents[1] / "scripts" / "search_planner.py"


def load_module():
    spec = importlib.util.spec_from_file_location("search_planner", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class SearchPlannerTests(unittest.TestCase):
    def test_interior_plan_includes_full_space_and_realism_queries(self):
        planner = load_module()
        ideas = planner.build_queries(
            "东方 新中式 书房 室内设计", "both", 12, interior=True
        )
        queries = "\n".join(idea.query.lower() for idea in ideas)
        self.assertIn("wide angle full room", queries)
        self.assertIn("realistic interior photography", queries)
        self.assertTrue(any("完整空间" in idea.query for idea in ideas))

    def test_count_is_bounded_to_sixteen(self):
        planner = load_module()
        ideas = planner.build_queries("study interior", "en", 99, interior=True)
        self.assertEqual(len(ideas), 16)


if __name__ == "__main__":
    unittest.main()
