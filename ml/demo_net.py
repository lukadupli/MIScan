import torch
import torch.nn as nn

# ---- A deliberately tiny 2-block net, so you extend it rather than copy it ----
class ToyNet(nn.Module):
    def __init__(self, out_values: int = 8):
        super().__init__()                      # ALWAYS first line

        # Assigning a layer to self.<name> REGISTERS it: torch then knows its
        # weights are parameters of this model. A layer stored in a plain list
        # or local variable is invisible to the optimiser and never trains.
        self.block1 = nn.Sequential(
            nn.Conv2d(3, 32, kernel_size=3, stride=2, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),
        )
        self.block2 = nn.Sequential(
            nn.Conv2d(32, 64, kernel_size=3, stride=2, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
        )
        self.head = nn.Sequential(
            nn.Flatten(),                       # (B, C, H, W) -> (B, C*H*W)
            nn.Linear(64 * 56 * 56, out_values),
        )

    def forward(self, x):                       # defines what happens to data
        x = self.block1(x)
        x = self.block2(x)
        return self.head(x)


net = ToyNet()
x = torch.zeros(2, 3, 224, 224)                 # batch of 2 fake images

# Call the MODULE, never .forward() directly -- hooks and train/eval mode
# are handled by __call__.
y = net(x)
print("input :", tuple(x.shape))
print("output:", tuple(y.shape), " <- (batch, 8)")
print("params:", f"{sum(p.numel() for p in net.parameters()):,}")

print("\n--- shapes stage by stage (how you debug a shape mismatch) ---")
h = x
for name, layer in [("block1", net.block1), ("block2", net.block2)]:
    h = layer(h)
    print(f"{name}: {tuple(h.shape)}")
print("flatten:", tuple(nn.Flatten()(h).shape))