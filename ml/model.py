import torch
import torch.nn as nn
from itertools import chain

class CornerNet(nn.Module):
    def __init__(self, out_size: int = 8):
        super().__init__()

        self.features = nn.Sequential(
            nn.Conv2d(3, 32, kernel_size=3, stride=2, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),

            nn.Conv2d(32, 64, kernel_size=3, stride=2, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),

            nn.Conv2d(64, 128, kernel_size=3, stride=2, padding=1),
            nn.BatchNorm2d(128),
            nn.ReLU(inplace=True),

            nn.Conv2d(128, 256, kernel_size=3, stride=2, padding=1),
            nn.BatchNorm2d(256),
            nn.ReLU(inplace=True),

            nn.Conv2d(256, 256, kernel_size=3, stride=2, padding=1),
            nn.BatchNorm2d(256),
            nn.ReLU(inplace=True)
        )

        self.head = nn.Sequential(
            nn.Flatten(),
            nn.Linear(7*7*256, out_size)
        )

    def forward(self, x):
        x = self.features(x)
        x = self.head(x)
        return x

if __name__ == "__main__":
    net = CornerNet()
    x = torch.zeros(3, 3, 224, 224)
    t = x
    print("----SHAPES----")
    print("Shape: ", t.shape)
    for l in chain(net.features.children(), net.head.children()):
        print(l)
        t = l(t)
        print("Shape: ", t.shape)

    print("---I/O, PARAMS---")
    print("input: ", x.shape)
    print("output: ", t.shape)
    print("params: ", sum([p.numel() for p in net.parameters()]))
    
    