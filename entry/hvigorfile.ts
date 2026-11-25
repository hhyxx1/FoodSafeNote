import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { HvigorPlugin } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

const preserveLauncherIcon: HvigorPlugin = {
    pluginId: 'preserve-launcher-icon',
    apply(node) {
        node.afterNodeEvaluate(() => {
            const task = node.getTaskByName('default@PackageHap');
            if (!task) return;

            const source = path.resolve(__dirname, '../AppScope/resources/base/media');
            const compiled = path.join(__dirname, 'build/default/intermediates/res/default/resources/base/media');
            // The API 26 resource compiler downsizes launcher layers to 512 px. Package the 1024 px originals.
            node.registerTask({
                name: 'preserveLauncherIcon',
                dependencies: ['default@ProcessCompiledResources'],
                postDependencies: ['default@PackageHap'],
                run() {
                    for (const layer of ['foreground.png', 'background.png']) {
                        const sourceFile = path.join(source, layer);
                        const compiledFile = path.join(compiled, layer);
                        if (!fs.readFileSync(sourceFile).equals(fs.readFileSync(compiledFile))) {
                            fs.copyFileSync(sourceFile, compiledFile);
                        }
                    }
                }
            });
        });
    }
};

export default {
    system: hapTasks,
    plugins: [preserveLauncherIcon]
}
