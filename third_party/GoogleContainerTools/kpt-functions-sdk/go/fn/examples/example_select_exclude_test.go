// Copyright 2022 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package example

import (
	"os"

	"github.com/nephio-project/porch/third_party/GoogleContainerTools/kpt-functions-sdk/go/fn"
)

// This example implements a function that selectively includes or excludes some resources.

func Example_selectExclude() {
	if err := fn.AsMain(fn.ResourceListProcessorFunc(selectResources)); err != nil {
		os.Exit(1)
	}
}

// selectResources keeps all resources with the GVK apps/v1 Deployment that do
// NOT have the label foo=bar, and removes the rest.
func selectResources(rl *fn.ResourceList) (bool, error) {
	rl.Items = rl.Items.Where(fn.IsGVK("apps", "v1", "Deployment")).
		WhereNot(fn.HasLabels(map[string]string{"foo": "bar"}))
	return true, nil
}
